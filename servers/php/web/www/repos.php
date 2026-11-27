<?php
declare(strict_types=1);

# Every repository URL in use by an enabled host: the names hosts give it,
# and which hosts use it. A repository is identified by its URL; the same
# name (FreeBSD-base, local) points at different URLs at different sites.

require __DIR__ . '/../include/common.php';

$repos = rows("
SELECT R.url,
       string_agg(DISTINCT HR.name, ', ')                  AS names,
       json_agg(DISTINCT H.name ORDER BY H.name)::text     AS hosts,
       (SELECT count(*) FROM host_package HP
                        JOIN host H2 ON H2.id = HP.host_id AND H2.enabled
         WHERE HP.repo_id = R.id)                          AS installs
  FROM repo R JOIN host_repo HR ON HR.repo_id = R.id
              JOIN host      H  ON H.id = HR.host_id AND H.enabled
 GROUP BY R.id, R.url
 ORDER BY R.url");

if (export_format()) {
  export('repositories', [
    'url' => 'url', 'names' => 'names', 'installs' => 'installs', 'hosts' => 'hosts',
  ], array_map(function ($r) {
    # hosts as a list in JSON, space-separated in CSV
    $hosts = json_decode($r['hosts'], true) ?: [];
    $r['hosts'] = export_format() === 'json' ? $hosts : implode(' ', $hosts);
    return $r;
  }, $repos));
}

page_header('Repositories');
?>
<p><?= count($repos) ?> repositories in use by enabled hosts.</p>
<?= export_links() ?>

<input type="search" class="filter" data-table="repos" data-columns="0 1" placeholder="Filter repositories" aria-label="Filter repositories">

<table id="repos" class="sortable">
<thead><tr><th>URL</th><th>Names</th><th class="num" title="packages installed from it, counted once per host">Installs</th><th>Hosts</th></tr></thead>
<tbody>
<?php foreach ($repos as $r):
  $hosts = json_decode($r['hosts'], true) ?: []; ?>
<tr>
  <td class="url"><a href="repo.php?url=<?= h(rawurlencode($r['url'])) ?>" title="the packages installed from this repository"><?= h($r['url']) ?></a></td>
  <td><?= $r['names'] === null ? '<span class="muted">not sent by these clients</span>' : h($r['names']) ?></td>
  <td class="num"><?= (int) $r['installs'] ?></td>
  <td data-sort="<?= count($hosts) ?>"><?= implode('<br>', array_map('host_link', $hosts)) ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php
page_footer();
