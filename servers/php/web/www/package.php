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

$total = count($hosts);
if ($older_than !== '') {
  $hosts = array_values(array_filter($hosts,
    fn($r) => pkg_version_cmp(split_package($r['package_version'])[1], $older_than) < 0));
}

# this page's address with some parameters changed, for links
$here = function (array $changes) use ($name, $all, $older_than): string {
  $q = array_filter(array_merge(['name' => $name, 'all' => $all ? '1' : '', 'older_than' => $older_than], $changes),
                    fn($v) => $v !== '');
  return 'package.php?' . http_build_query($q);
};

if (export_format()) {
  export('hosts-with-' . $name . ($older_than === '' ? '' : '-older-than-' . $older_than) . ($all ? '-all' : ''), [
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
<?php if ($older_than !== ''): ?>
  <a href="<?= h($here(['older_than' => ''])) ?>">Show every version</a>
<?php endif; ?>
</form>

<?php if ($versions !== []): ?>
<h2>Versions</h2>
<table class="versions">
<thead><tr><th>Version</th><th class="num">Hosts</th><th></th></tr></thead>
<tbody>
<?php foreach ($versions as $v => $n):
  $v = (string) $v;
  $is_older = $older_than !== '' && pkg_version_cmp($v, $older_than) < 0; ?>
<tr<?= $is_older ? ' class="older"' : '' ?>>
  <td class="mono"><?= h($v) ?></td>
  <td class="num"><?= $n ?></td>
  <td><?= $is_older ? '<span class="tag older">older</span>' : '' ?>
      <a href="<?= h($here(['older_than' => $v])) ?>">hosts older than this</a></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php endif; ?>

<?php if ($older_than === ''): ?>
<h2>Hosts</h2>
<?php else: ?>
<h2>Hosts with a version older than <span class="mono"><?= h($older_than) ?></span></h2>
<p><?= count($hosts) ?> of <?= $total ?> hosts.</p>
<?php endif; ?>
<?php if ($hosts === []): ?>
<p><?= $older_than === '' ? 'No host has this package installed now.' : 'None: every host has this version or newer.' ?></p>
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
