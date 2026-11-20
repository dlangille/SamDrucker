<?php
declare(strict_types=1);

# Shared code for the SamDrucker reporting website: configuration, the
# database connection, and the page header and footer.
#
# The website only reads. It connects as a member of the reporting role,
# which has SELECT and nothing else, so no page can change the data.

const CONF_FILE = '/usr/local/etc/samdrucker/samdruckerweb.conf';

# a host which has not checked in for this long is shown as stale; the
# same limit as PostgreSQL/check_samdrucker_host_checkins
const STALE_HOURS = 25;

if (!is_readable(CONF_FILE)) {
  syslog(LOG_ERR, 'samdrucker web: ' . CONF_FILE . ' is missing or unreadable');
  http_response_code(500);
  exit('The website is not configured. See servers/php/web/README.md.');
}

$host = $port = $db = $user = $password = null;
require CONF_FILE;

# Escape a value for HTML. Every value from the database goes through this.
function h(?string $s): string {
  return htmlspecialchars($s ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function db(): PDO {
  static $dbh = null;
  global $host, $port, $db, $user, $password;

  if ($dbh === null) {
    $dsn = "pgsql:host=$host;port=$port;dbname=$db;sslmode=require";
    try {
      $dbh = new PDO($dsn, $user, $password, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
      ]);
      # belt and braces: the role cannot write anyway
      $dbh->exec('SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY');
    } catch (PDOException $e) {
      syslog(LOG_ERR, 'samdrucker web: cannot connect to the database: ' . $e->getMessage());
      http_response_code(503);
      exit('Cannot connect to the database.');
    }
  }
  return $dbh;
}

# Run a query with bound parameters and return all rows.
function rows(string $sql, array $params = []): array {
  $stmt = db()->prepare($sql);
  $stmt->execute($params);
  return $stmt->fetchAll();
}

# A string parameter from the query string, or '' when absent.
function param(string $name): string {
  $v = $_GET[$name] ?? '';
  return is_string($v) ? trim($v) : '';
}

function host_link(string $name): string {
  return '<a class="mono" href="host.php?name=' . h(rawurlencode($name)) . '">' . h($name) . '</a>';
}

function package_link(string $name, ?string $text = null): string {
  return '<a class="mono" href="package.php?name=' . h(rawurlencode($name)) . '">' . h($text ?? $name) . '</a>';
}

# Split "php85-8.5.0" into ["php85", "8.5.0"] the way HostAddPackages()
# does: on the rightmost hyphen.
function split_package(string $package_version): array {
  $i = strrpos($package_version, '-');
  return $i === false ? [$package_version, ''] : [substr($package_version, 0, $i), substr($package_version, $i + 1)];
}

# host.date_updated is a UTC timestamp without a time zone.
function age(?string $utc): string {
  if ($utc === null) {
    return '';
  }
  $seconds = time() - (new DateTimeImmutable($utc, new DateTimeZone('UTC')))->getTimestamp();
  return match (true) {
    $seconds < 3600      => intdiv(max($seconds, 0), 60) . ' min ago',
    $seconds < 2 * 86400 => intdiv($seconds, 3600) . ' h ago',
    default              => intdiv($seconds, 86400) . ' days ago',
  };
}

function utc(?string $utc): string {
  return $utc === null ? '' : substr($utc, 0, 16) . ' UTC';
}

# $mono: show the heading in a fixed-width font, for a hostname or a
# package name
function page_header(string $title, bool $mono = false): void {
  header('Content-Type: text/html; charset=UTF-8');
  header("Content-Security-Policy: default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
  header('X-Content-Type-Options: nosniff');
  header('Referrer-Policy: no-referrer');
  header('X-Robots-Tag: noindex, nofollow');

  $nav = ['index.php' => 'Hosts', 'packages.php' => 'Packages', 'repos.php' => 'Repositories'];
  $self = basename($_SERVER['SCRIPT_NAME'] ?? '');
  ?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title><?= h($title) ?> - SamDrucker</title>
<link rel="stylesheet" href="samdrucker.css">
<script src="samdrucker.js" defer></script>
</head>
<body>
<header>
  <a class="brand" href="index.php">SamDrucker</a>
  <nav>
<?php foreach ($nav as $file => $label): ?>
    <a href="<?= h($file) ?>"<?= $self === $file ? ' aria-current="page"' : '' ?>><?= h($label) ?></a>
<?php endforeach; ?>
  </nav>
  <form action="packages.php" method="get" role="search">
    <input type="search" name="q" placeholder="Find a package" aria-label="Find a package" value="<?= h($self === 'packages.php' ? param('q') : '') ?>">
  </form>
</header>
<main>
<h1<?= $mono ? ' class="mono"' : '' ?>><?= h($title) ?></h1>
<?php
}

function page_footer(): void {
  ?>
</main>
<footer>
  Times are UTC. A host is <span class="stale">stale</span> when it has not checked in for <?= STALE_HOURS ?> hours.
</footer>
</body>
</html>
<?php
}

# Exports. Every page with a result table accepts ?format=csv or
# ?format=json, together with its usual parameters, and sends that table
# as a file to save instead of the HTML page.

const EXPORT_FORMATS = ['csv', 'json'];

# The export format asked for, or null for the normal HTML page.
function export_format(): ?string {
  $f = param('format');
  return in_array($f, EXPORT_FORMATS, true) ? $f : null;
}

# Links to the current page, with the same parameters, as CSV and as JSON.
function export_links(): string {
  $links = [];
  foreach (EXPORT_FORMATS as $f) {
    $query = array_merge($_GET, ['format' => $f]);
    $url = basename($_SERVER['SCRIPT_NAME'] ?? '') . '?' . http_build_query($query);
    $links[] = '<a href="' . h($url) . '" download>' . strtoupper($f) . '</a>';
  }
  return '<p class="export">Download: ' . implode(' ', $links) . '</p>';
}

# A spreadsheet treats a cell starting with = + - @ (or tab or CR) as a
# formula. Hosts can post any text they like, so such values get a leading
# apostrophe in CSV, which makes the spreadsheet show them as plain text.
function csv_safe(mixed $v): mixed {
  if (is_bool($v)) {
    return $v ? 'true' : 'false';
  }
  if (is_string($v) && $v !== '' && strpbrk($v[0], "=+-@\t\r") !== false) {
    return "'" . $v;
  }
  return $v;
}

# Send $rows as a file named <$basename>-<UTC date and time>.<format>, and
# stop. $columns maps each row key to its column heading, in order.
function export(string $basename, array $columns, array $rows): never {
  $format = export_format();
  $basename = preg_replace('/[^A-Za-z0-9._-]+/', '_', $basename);
  $filename = $basename . '-' . gmdate('Ymd\THis\Z') . '.' . $format;

  header('X-Content-Type-Options: nosniff');
  header('X-Robots-Tag: noindex, nofollow');
  header('Content-Disposition: attachment; filename="' . $filename . '"');

  $out = [];
  foreach ($rows as $r) {
    $o = [];
    # CSV and JSON use the same names: the headings
    foreach ($columns as $key => $heading) {
      $o[$heading] = $r[$key] ?? null;
    }
    $out[] = $o;
  }

  if ($format === 'json') {
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), "\n";
  } else {
    header('Content-Type: text/csv; charset=UTF-8');
    $fh = fopen('php://output', 'w');
    fputcsv($fh, array_values($columns), ',', '"', '');
    foreach ($out as $o) {
      fputcsv($fh, array_map('csv_safe', array_values($o)), ',', '"', '');
    }
    fclose($fh);
  }
  exit;
}

function not_found(string $message): never {
  http_response_code(404);
  page_header('Not found');
  echo '<p>' . h($message) . '</p>';
  page_footer();
  exit;
}
