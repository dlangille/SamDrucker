<?php
declare(strict_types=1);

# Find packages by part of their name. Counts only enabled hosts.
# Without a search term, lists every package installed on any enabled host.

require __DIR__ . '/../include/common.php';

const LIMIT = 1000;

$q = param('q');

# strpos() rather than LIKE, so % and _ in the search term are literal
$packages = rows("
SELECT P.name,
       count(DISTINCT HP.host_id) AS hosts,
       count(DISTINCT PV.id)      AS versions
  FROM package P JOIN package_version PV ON PV.package_id = P.id
                 JOIN host_package    HP ON HP.package_version_id = PV.id
                 JOIN host            H  ON H.id = HP.host_id AND H.enabled
 WHERE :q = '' OR strpos(lower(P.name), lower(:q)) > 0
 GROUP BY P.name
 ORDER BY P.name
 LIMIT " . (LIMIT + 1), ['q' => $q]);

$more = count($packages) > LIMIT;
$packages = array_slice($packages, 0, LIMIT);

if (export_format()) {
  export($q === '' ? 'packages' : 'packages-matching-' . $q, [
    'name' => 'package', 'hosts' => 'hosts', 'versions' => 'versions',
  ], $packages);
}

page_header($q === '' ? 'Packages' : "Packages matching \"$q\"");
?>
<p>
  <?= count($packages) ?><?= $more ? '+' : '' ?> packages installed on enabled hosts.
  <?= $more ? 'Only the first ' . LIMIT . ' are shown, and downloaded; search for something narrower.' : '' ?>
</p>
<?= export_links() ?>

<?php if (count($packages) === 1 && $q !== ''): ?>
<p>Only one match: <?= package_link($packages[0]['name']) ?>.</p>
<?php endif; ?>

<input type="search" class="filter" data-table="packages" data-columns="0" placeholder="Filter packages" aria-label="Filter packages">

<table id="packages" class="sortable">
<thead><tr><th>Package</th><th class="num">Hosts</th><th class="num">Versions</th></tr></thead>
<tbody>
<?php foreach ($packages as $r): ?>
<tr>
  <td><?= package_link($r['name']) ?></td>
  <td class="num"><?= (int) $r['hosts'] ?></td>
  <td class="num"><?= (int) $r['versions'] ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php
page_footer();
