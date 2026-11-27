<?php
declare(strict_types=1);

# One repository, given by its URL (?url=): every package that enabled
# hosts installed from it, with how many hosts have it from here and in
# how many versions. Each package links to its page, narrowed to the
# hosts which installed it from this repository.

require __DIR__ . '/../include/common.php';

$url = param('url');
if ($url === '') {
  not_found('No repository given.');
}

$repo = rows('SELECT id, url FROM repo WHERE url = :url', ['url' => $url])[0] ?? null;
if ($repo === null) {
  not_found("There is no repository with the URL $url.");
}

# the names enabled hosts give this repository, and how many use it
$about = rows("
SELECT string_agg(DISTINCT HR.name, ', ') AS names,
       count(DISTINCT HR.host_id)         AS hosts
  FROM host_repo HR JOIN host H ON H.id = HR.host_id AND H.enabled
 WHERE HR.repo_id = :id", ['id' => $repo['id']])[0];

$packages = rows("
SELECT P.name,
       count(DISTINCT HP.host_id) AS hosts,
       count(DISTINCT PV.id)      AS versions
  FROM host_package HP JOIN host            H  ON H.id  = HP.host_id AND H.enabled
                       JOIN package_version PV ON PV.id = HP.package_version_id
                       JOIN package         P  ON P.id  = PV.package_id
 WHERE HP.repo_id = :id
 GROUP BY P.name
 ORDER BY P.name", ['id' => $repo['id']]);

if (export_format()) {
  export('packages-from-' . $repo['url'], [
    'name' => 'package', 'hosts' => 'hosts', 'versions' => 'versions',
  ], $packages);
}

page_header($repo['url'], true);
?>
<dl class="facts">
  <dt>Names</dt>
  <dd><?= $about['names'] === null ? '<span class="muted">not sent by these clients</span>' : h($about['names']) ?></dd>
  <dt>Enabled hosts using it</dt>
  <dd><?= (int) $about['hosts'] ?></dd>
  <dt>Packages installed from it</dt>
  <dd><?= count($packages) ?></dd>
</dl>

<h2>Packages</h2>
<?php if ($packages === [] && $about['names'] === null && (int) $about['hosts'] > 0): ?>
<p>None recorded. The hosts using this repository run an older client (0.2.x),
   which does not say which repository each package came from.</p>
<?php elseif ($packages === []): ?>
<p>No enabled host has a package installed from this repository.</p>
<?php else: ?>
<?= export_links() ?>
<input type="search" class="filter" data-table="packages" data-columns="0" placeholder="Filter packages" aria-label="Filter packages">

<table id="packages" class="sortable">
<thead><tr><th>Package</th><th class="num">Hosts</th><th class="num">Versions</th></tr></thead>
<tbody>
<?php foreach ($packages as $r): ?>
<tr>
  <td><a class="mono" href="<?= h('package.php?' . http_build_query(['name' => $r['name'], 'repo' => $repo['url']])) ?>"
         title="the hosts which installed <?= h($r['name']) ?> from this repository"><?= h($r['name']) ?></a></td>
  <td class="num"><?= (int) $r['hosts'] ?></td>
  <td class="num"><?= (int) $r['versions'] ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php endif; ?>
<?php
page_footer();
