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

# Compare two FreeBSD package versions the way pkg does: -1, 0 or 1 as $a
# is older than, the same as, or newer than $b, exactly as
# `pkg version -t $a $b` prints <, = or >. Either may be a bare version
# (1.30.7_1,3) or a package name and version (nginx-1.30.7_1,3).
#
# This is a line-for-line port of pkg_version_cmp() and its helpers from
# libpkg/pkg_version.c in pkg (https://github.com/freebsd/pkg); see the
# comments there for the rules. In short: the epoch (,3) counts first,
# then the version, then the port revision (_1), so 1.30.7_1,3 is newer
# than 1.30.7,3. Plain string or PHP version_compare() ordering gets
# cases like that, and epochs, wrong.

function pkg_version_cmp(string $a, string $b): int {
  [$v1, $ve1, $e1, $r1] = pkg_version_split($a);
  [$v2, $ve2, $e2, $r2] = pkg_version_split($b);
  $result = 0;

  # epoch, then version, then revision
  if ($e1 !== $e2) {
    $result = $e1 < $e2 ? -1 : 1;
  }

  if ($result === 0 && ($ve1 !== $ve2 || strncasecmp($v1, $v2, $ve1) !== 0)) {
    $p1 = 0;
    $p2 = 0;
    while ($result === 0 && ($p1 < $ve1 || $p2 < $ve2)) {
      $block1 = $block2 = false;
      $c1 = $c2 = ['n' => 0, 'a' => 0, 'pl' => 0];
      if ($p1 < $ve1 && $v1[$p1] !== '+') {
        $p1 = pkg_version_component($v1, $p1, $c1);
      } else {
        $block1 = true;
      }
      if ($p2 < $ve2 && $v2[$p2] !== '+') {
        $p2 = pkg_version_component($v2, $p2, $c2);
      } else {
        $block2 = true;
      }
      if ($block1 && $block2) {
        if ($p1 < $ve1) $p1++;
        if ($p2 < $ve2) $p2++;
      } elseif ($c1['n'] !== $c2['n']) {
        $result = $c1['n'] < $c2['n'] ? -1 : 1;
      } elseif ($c1['a'] !== $c2['a']) {
        $result = $c1['a'] < $c2['a'] ? -1 : 1;
      } elseif ($c1['pl'] !== $c2['pl']) {
        $result = $c1['pl'] < $c2['pl'] ? -1 : 1;
      }
    }
  }

  if ($result === 0 && $r1 !== $r2) {
    $result = $r1 < $r2 ? -1 : 1;
  }
  return $result;
}

# split_version(): the version string (after the last '-'), the length of
# its version part (before the revision and epoch), the epoch and the
# revision.
function pkg_version_split(string $s): array {
  $dash = strrpos($s, '-');
  $v = $dash === false ? $s : substr($s, $dash + 1);

  $underscore = strrpos($v, '_');
  $revision = $underscore === false ? 0 : pkg_version_strtoul(substr($v, $underscore + 1));
  $end = $underscore === false ? null : $underscore;

  $comma = strrpos($v, ',', $underscore === false ? 0 : $underscore + 1);
  $epoch = $comma === false ? 0 : pkg_version_strtoul(substr($v, $comma + 1));
  if ($comma !== false && $end === null) {
    $end = $comma;
  }

  return [$v, $end ?? strlen($v), $epoch, $revision];
}

# strtoul(): the leading digits as a number, 0 if there are none
function pkg_version_strtoul(string $s): int {
  return preg_match('/^\s*\+?(\d+)/', $s, $m) ? (int) $m[1] : 0;
}

# isdigit() and isalpha() in the C locale; '' stands for the end of the string
function pkg_version_isdigit(string $c): bool {
  return $c !== '' && $c >= '0' && $c <= '9';
}
function pkg_version_isalpha(string $c): bool {
  return $c !== '' && (($c >= 'a' && $c <= 'z') || ($c >= 'A' && $c <= 'Z'));
}

# get_component(): parse one component (number, letter, patch level)
# starting at $pos into $c, and return the position after it and any
# separators which follow.
function pkg_version_component(string $v, int $pos, array &$c): int {
  # pl sorts before every letter; the others sort by their first letter
  static $stages = [['pl', 0], ['snap', 20], ['alpha', 2], ['beta', 3], ['pre', 17], ['rc', 19]];
  $at = fn(int $i): string => $i < strlen($v) ? $v[$i] : '';
  $hasstage = false;
  $haspatchlevel = false;

  # version number
  if (pkg_version_isdigit($at($pos))) {
    preg_match('/\d+/A', $v, $m, 0, $pos);
    $c['n'] = (int) $m[0];
    $pos += strlen($m[0]);
  } elseif ($at($pos) === '*') {
    $c['n'] = -2;
    do {
      $pos++;
    } while ($at($pos) !== '' && $at($pos) !== '+');
  } else {
    $c['n'] = -1;
    $hasstage = true;
  }

  # letter
  if (pkg_version_isalpha($at($pos))) {
    $letter = strtolower($at($pos));
    $haspatchlevel = true;
    if (pkg_version_isalpha($at($pos + 1))) {
      foreach ($stages as [$name, $value]) {
        $len = strlen($name);
        if (strncasecmp(substr($v, $pos), $name, $len) === 0 && !pkg_version_isalpha($at($pos + $len))) {
          if ($hasstage) {
            $c['a'] = $value;
            $pos += $len;
          } else {
            # insert a dot: the stage starts the next component
            $c['a'] = 0;
            $haspatchlevel = false;
          }
          $letter = '';
          break;
        }
      }
    }
    if ($letter !== '') {
      # use the first letter and skip the rest
      $c['a'] = ord($letter) - ord('a') + 2;
      do {
        $pos++;
      } while (pkg_version_isalpha($at($pos)));
    }
  } else {
    $c['a'] = 0;
    $haspatchlevel = false;
  }

  # patch level
  if ($haspatchlevel) {
    if (pkg_version_isdigit($at($pos))) {
      preg_match('/\d+/A', $v, $m, 0, $pos);
      $c['pl'] = (int) $m[0];
      $pos += strlen($m[0]);
    } else {
      $c['pl'] = -1;
    }
  } else {
    $c['pl'] = 0;
  }

  # skip separators
  while ($at($pos) !== '' && !pkg_version_isdigit($at($pos)) && !pkg_version_isalpha($at($pos))
         && $at($pos) !== '+' && $at($pos) !== '*') {
    $pos++;
  }
  return $pos;
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

# Exports. Every page with a result table accepts ?format=csv, ?format=tsv
# or ?format=json, together with its usual parameters, and sends that
# table as a file to save instead of the HTML page.

const EXPORT_FORMATS = ['csv', 'tsv', 'json'];

# The export format asked for, or null for the normal HTML page.
function export_format(): ?string {
  $f = param('format');
  return in_array($f, EXPORT_FORMATS, true) ? $f : null;
}

# Links to the current page, with the same parameters, in each format.
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
# apostrophe in CSV and TSV, which makes the spreadsheet show them as
# plain text.
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
    # every format uses the same names: the headings
    foreach ($columns as $key => $heading) {
      $o[$heading] = $r[$key] ?? null;
    }
    $out[] = $o;
  }

  if ($format === 'json') {
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), "\n";
  } else if ($format === 'tsv') {
    # Tab-separated values have no quoting, so a tab or line break inside
    # a value would split it; each becomes a space.
    header('Content-Type: text/tab-separated-values; charset=UTF-8');
    $line = fn(array $values): string =>
      implode("\t", array_map(fn($v) => str_replace(["\t", "\r", "\n"], ' ', (string) $v), $values)) . "\n";
    echo $line(array_values($columns));
    foreach ($out as $o) {
      echo $line(array_map('csv_safe', array_values($o)));
    }
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
