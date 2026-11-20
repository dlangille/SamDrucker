<?php
declare(strict_types=1);

# One host: its details, its repositories, and every installed package
# with the repository it came from. Shown for disabled hosts too.

require __DIR__ . '/../include/common.php';

$name = param('name');
if ($name === '') {
  not_found('No host given.');
}

$host = rows("
SELECT name, os, version, repo, enabled, date_updated,
       timezone('UTC', now()) - date_updated > make_interval(hours => :stale) AS stale
  FROM host
 WHERE name = :name", ['name' => $name, 'stale' => STALE_HOURS])[0] ?? null;

if ($host === null) {
  not_found("There is no host named $name.");
}

$repos    = rows('SELECT name, url, priority FROM ReposOnHost(:name)', ['name' => $name]);
$packages = rows('SELECT package_version, repo_name, url FROM PackagesOnHostShowRepo(:name)', ['name' => $name]);

if (export_format()) {
  export('packages-' . $host['name'], [
    'package' => 'package', 'version' => 'version', 'repo_name' => 'repository', 'url' => 'url',
  ], array_map(function ($p) {
    [$p['package'], $p['version']] = split_package($p['package_version']);
    return $p;
  }, $packages));
}

page_header($host['name']);
?>
<dl class="facts">
  <dt>Status</dt>
  <dd><?= $host['enabled'] ? 'enabled' : '<span class="tag">disabled</span>' ?></dd>
  <dt>OS version</dt>
  <dd><?= h($host['os'] . ' ' . $host['version']) ?></dd>
  <dt>Last check-in</dt>
  <dd><?= h(utc($host['date_updated'])) ?> (<?= h(age($host['date_updated'])) ?>)<?= $host['stale'] && $host['enabled'] ?' <span class="stale">stale</span>' : '' ?></dd>
  <dt>Packages</dt>
  <dd><?= count($packages) ?></dd>
</dl>

<h2>Repositories</h2>
<?php if ($repos === []): ?>
<p>None recorded.</p>
<?php else: ?>
<table>
<thead><tr><th>Name</th><th>URL</th><th class="num">Priority</th><th class="num">Packages</th></tr></thead>
<tbody>
<?php foreach ($repos as $r):
  $n = count(array_filter($packages, fn($p) => $p['url'] === $r['url'])); ?>
<tr>
  <td><?= $r['name'] === null ? '<span class="muted">not sent by this client</span>' : h($r['name']) ?></td>
  <td class="url"><?= h($r['url']) ?></td>
  <td class="num"><?= (int) $r['priority'] ?></td>
  <td class="num"><?= $n ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php endif; ?>

<h2>Packages</h2>
<?= export_links() ?>
<input type="search" class="filter" data-table="packages" placeholder="Filter packages" aria-label="Filter packages">

<table id="packages" class="sortable">
<thead><tr><th>Package</th><th>Version</th><th>Repository</th></tr></thead>
<tbody>
<?php foreach ($packages as $p):
  [$pname, $pversion] = split_package($p['package_version']); ?>
<tr>
  <td><?= package_link($pname) ?></td>
  <td><?= h($pversion) ?></td>
  <td><?= $p['repo_name'] === null ? '<span class="muted">unknown</span>' : h($p['repo_name']) ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php
page_footer();
