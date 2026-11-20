<?php
declare(strict_types=1);

# One package: which hosts have it, in which version, from which
# repository, with a count of hosts per version. ?all=1 adds disabled hosts.

require __DIR__ . '/../include/common.php';

$name = param('name');
if ($name === '') {
  not_found('No package given.');
}

$all = param('all') === '1';

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

# hosts per version, newest version first
$versions = [];
foreach ($hosts as $r) {
  [, $v] = split_package($r['package_version']);
  $versions[$v] = ($versions[$v] ?? 0) + 1;
}
uksort($versions, fn($a, $b) => version_compare((string) $b, (string) $a));

if (export_format()) {
  export('hosts-with-' . $name . ($all ? '-all' : ''), [
    'host' => 'host', 'enabled' => 'host_enabled', 'package' => 'package', 'version' => 'version',
    'repo_name' => 'repository', 'url' => 'url',
  ], array_map(function ($r) {
    [$r['package'], $r['version']] = split_package($r['package_version']);
    return $r;
  }, $hosts));
}

page_header($name);
?>
<p>
  <?= count($hosts) ?> hosts<?= $all ? ', including disabled ones' : '' ?>.
  <a href="package.php?name=<?= h(rawurlencode($name)) ?><?= $all ? '' : '&amp;all=1' ?>"><?= $all ? 'Hide disabled hosts' : 'Show disabled hosts' ?></a>
</p>
<?= $hosts === [] ? '' : export_links() ?>

<?php if ($versions !== []): ?>
<h2>Versions</h2>
<table>
<thead><tr><th>Version</th><th class="num">Hosts</th></tr></thead>
<tbody>
<?php foreach ($versions as $v => $n): ?>
<tr><td><?= h((string) $v) ?></td><td class="num"><?= $n ?></td></tr>
<?php endforeach; ?>
</tbody>
</table>
<?php endif; ?>

<h2>Hosts</h2>
<?php if ($hosts === []): ?>
<p>No host has this package installed now.</p>
<?php else: ?>
<input type="search" class="filter" data-table="hosts" placeholder="Filter hosts" aria-label="Filter hosts">

<table id="hosts" class="sortable">
<thead><tr><th>Host</th><th>Version</th><th>Repository</th></tr></thead>
<tbody>
<?php foreach ($hosts as $r):
  [, $v] = split_package($r['package_version']); ?>
<tr<?= $r['enabled'] ? '' : ' class="disabled"' ?>>
  <td><?= host_link($r['host']) ?><?= $r['enabled'] ? '' : ' <span class="tag">disabled</span>' ?></td>
  <td><?= h($v) ?></td>
  <td title="<?= h($r['url']) ?>"><?= $r['repo_name'] === null ? '<span class="muted">unknown</span>' : h($r['repo_name']) ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php endif; ?>
<?php
page_footer();
