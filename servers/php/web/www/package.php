<?php
declare(strict_types=1);

# One package: which hosts have it, in which version, from which
# repository, with a count of hosts per version. ?all=1 adds disabled hosts.
#
# ?older_than=VERSION shows only the hosts whose version is older than
# VERSION, compared the way pkg does (see pkg_version_cmp()); downloads then
# hold only those hosts too. This answers "which hosts need this security
# update?". VERSION may also be given as the package name and version, as
# security advisories write it: nginx-1.30.7,3.
#
# ?version=VERSION shows only the hosts with exactly that version.

require __DIR__ . '/../include/common.php';

$name = param('name');
if ($name === '') {
  not_found('No package given.');
}

$all = param('all') === '1';

$older_than = param('older_than');
if (str_starts_with($older_than, $name . '-')) {
  $older_than = substr($older_than, strlen($name) + 1);
}
if (strlen($older_than) > 100 || preg_match('/\s/', $older_than)) {
  $older_than = '';
}

# ?version=VERSION shows only the hosts with exactly that version. It is
# what the host count beside each version links to. When both are given,
# version wins: the links never set both.
$version = param('version');
if (strlen($version) > 100 || preg_match('/\s/', $version)) {
  $version = '';
}
if ($version !== '') {
  $older_than = '';
}

$hosts = rows('SELECT host, package_version, repo_name, url, true AS enabled
                 FROM HostsWithPackageShowRepo(:name, true)', ['name' => $name]);
if ($all) {
  $hosts = array_merge($hosts,
    rows('SELECT host, package_version, repo_name, url, false AS enabled
            FROM HostsWithPackageShowRepo(:name, false)', ['name' => $name]));
}

if ($hosts === [] && !$all) {
  $known = rows('SELECT 1 FROM package WHERE name = :name', ['name' => $name]);
  if ($known === []) {
    not_found("No host has ever reported a package named $name.");
  }
}

# hosts per version, newest version first, over all the hosts
$versions = [];
foreach ($hosts as $r) {
  [, $v] = split_package($r['package_version']);
  $versions[$v] = ($versions[$v] ?? 0) + 1;
}
uksort($versions, fn($a, $b) => pkg_version_cmp((string) $b, (string) $a));

# for each version, how many hosts have an older one: the count shown on
# its "older" link, so the link says what it will list
$older_counts = [];
foreach ($versions as $v => $n) {
  $older_counts[$v] = 0;
  foreach ($versions as $w => $m) {
    if (pkg_version_cmp((string) $w, (string) $v) < 0) {
      $older_counts[$v] += $m;
    }
  }
}

# A version typed without an epoch (1.30.7 rather than 1.30.7,3) has
# epoch 0, and pkg compares epochs first, so every installed version with
# an epoch counts as newer and the filter shows nothing. That is never
# what anyone means. When every installed version of this package has the
# same epoch, assume it, and say so. When they differ, do not guess:
# explain, and offer the choices.
$epoch_note = '';
$epoch_choices = [];
if ($older_than !== '' && !str_contains($older_than, ',')) {
  $epochs = array_unique(array_map(fn($v) => pkg_version_split((string) $v)[2], array_keys($versions)));
  sort($epochs);
  if (count($epochs) === 1 && $epochs[0] > 0) {
    $epoch_note = "$older_than has no epoch; every installed $name has epoch $epochs[0], "
                . "so this compares against $older_than,$epochs[0].";
    $older_than .= ',' . $epochs[0];
  } elseif (count(array_filter($epochs)) > 0) {
    $epoch_choices = array_map(fn($e) => $e === 0 ? $older_than : "$older_than,$e", $epochs);
  }
}

$total = count($hosts);
if ($older_than !== '') {
  $hosts = array_values(array_filter($hosts,
    fn($r) => pkg_version_cmp(split_package($r['package_version'])[1], $older_than) < 0));
} elseif ($version !== '') {
  $hosts = array_values(array_filter($hosts,
    fn($r) => split_package($r['package_version'])[1] === $version));
}

# this page's address with some parameters changed, for links
$here = function (array $changes) use ($name, $all, $older_than, $version): string {
  $q = array_filter(array_merge(['name' => $name, 'all' => $all ? '1' : '',
                                 'older_than' => $older_than, 'version' => $version], $changes),
                    fn($v) => $v !== '');
  return 'package.php?' . http_build_query($q);
};

if (export_format()) {
  export('hosts-with-' . $name
         . ($older_than === '' ? '' : '-older-than-' . $older_than)
         . ($version === '' ? '' : '-version-' . $version)
         . ($all ? '-all' : ''), [
    'host' => 'host', 'enabled' => 'host_enabled', 'package' => 'package', 'version' => 'version',
    'repo_name' => 'repository', 'url' => 'url',
  ], array_map(function ($r) {
    [$r['package'], $r['version']] = split_package($r['package_version']);
    return $r;
  }, $hosts));
}

page_header($name, true);
?>
<p>
  <?= $total ?> hosts<?= $all ? ', including disabled ones' : '' ?>.
  <a href="<?= h($here(['all' => $all ? '' : '1'])) ?>"><?= $all ? 'Hide disabled hosts' : 'Show disabled hosts' ?></a>
</p>

<form class="older-than" method="get" action="package.php">
  <input type="hidden" name="name" value="<?= h($name) ?>">
<?php if ($all): ?>
  <input type="hidden" name="all" value="1">
<?php endif; ?>
  <label>Only hosts with a version older than
    <input type="text" name="older_than" class="mono" size="20" value="<?= h($older_than) ?>" placeholder="for example 1.30.7,3" spellcheck="false" autocapitalize="off">
  </label>
  <button type="submit">Show</button>
<?php if ($older_than !== '' || $version !== ''): ?>
  <a href="<?= h($here(['older_than' => '', 'version' => ''])) ?>">Show every version</a>
<?php endif; ?>
</form>
<?php if ($epoch_note !== ''): ?>
<p class="note"><?= h($epoch_note) ?></p>
<?php elseif ($epoch_choices !== []): ?>
<p class="note">
  <span class="mono"><?= h($older_than) ?></span> has no epoch, and the installed versions of
  <span class="mono"><?= h($name) ?></span> have different epochs. pkg compares the epoch first,
  so a version without one is older than every version with one. Compare against:
  <?= implode(', ', array_map(fn($c) => '<a class="mono" href="' . h($here(['older_than' => $c])) . '">' . h($c) . '</a>', $epoch_choices)) ?>
</p>
<?php endif; ?>

<?php if ($versions !== []): ?>
<h2>Versions</h2>
<table class="versions">
<thead><tr><th>Version</th><th class="num">Hosts on it</th><th>Hosts on an older version</th></tr></thead>
<tbody>
<?php foreach ($versions as $v => $n):
  $older = $older_counts[$v];
  $v = (string) $v;
  $is_older = $older_than !== '' && pkg_version_cmp($v, $older_than) < 0; ?>
<tr<?= $is_older ? ' class="older"' : '' ?>>
  <td class="mono"><?= $is_older ? '<span class="tag older">older</span>' : '' ?><?= h($v) ?></td>
  <td class="num"><a href="<?= h($here(['version' => $v, 'older_than' => ''])) ?>"
      title="the hosts with <?= h($v) ?>"><?= $n ?></a></td>
  <td><?php if ($older > 0): ?><a href="<?= h($here(['older_than' => $v, 'version' => ''])) ?>"
      title="the hosts with a version older than <?= h($v) ?>"><?= $older ?> <?= $older === 1 ? 'host' : 'hosts' ?> older than <?= h($v) ?></a><?php else: ?><span class="muted">none</span><?php endif; ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php endif; ?>

<?php if ($version !== ''): ?>
<h2>Hosts with version <span class="mono"><?= h($version) ?></span></h2>
<p><?= count($hosts) ?> of <?= $total ?> hosts.</p>
<?php elseif ($older_than === ''): ?>
<h2>Hosts</h2>
<?php else: ?>
<h2>Hosts with a version older than <span class="mono"><?= h($older_than) ?></span></h2>
<p><?= count($hosts) ?> of <?= $total ?> hosts.</p>
<?php endif; ?>
<?php if ($hosts === []): ?>
<p><?= $version !== '' ? 'None: no host has this version.'
      : ($older_than === '' ? 'No host has this package installed now.' : 'None: every host has this version or newer.') ?></p>
<?php else: ?>
<?= export_links() ?>
<input type="search" class="filter" data-table="hosts" placeholder="Filter hosts" aria-label="Filter hosts">

<table id="hosts" class="sortable">
<thead><tr><th>Host</th><th>Version</th><th>Repository</th></tr></thead>
<tbody>
<?php foreach ($hosts as $r):
  [, $v] = split_package($r['package_version']); ?>
<tr<?= $r['enabled'] ? '' : ' class="disabled"' ?>>
  <td><?= host_link($r['host']) ?><?= $r['enabled'] ? '' : ' <span class="tag">disabled</span>' ?></td>
  <td class="mono"><?= h($v) ?></td>
  <td title="<?= h($r['url']) ?>"><?= $r['repo_name'] === null ? '<span class="muted">unknown</span>' : h($r['repo_name']) ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php endif; ?>
<?php
page_footer();
