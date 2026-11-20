<?php
declare(strict_types=1);

# Every host: what it runs, when it last checked in, how many packages it
# has, and which repositories it uses. ?all=1 includes disabled hosts.

require __DIR__ . '/../include/common.php';

$all = param('all') === '1';

$hosts = rows("
SELECT H.name, H.os, H.version, H.enabled, H.date_updated,
       timezone('UTC', now()) - H.date_updated > make_interval(hours => :stale) AS stale,
       (SELECT count(*) FROM host_package HP WHERE HP.host_id = H.id) AS packages,
       (SELECT string_agg(coalesce(HR.name, R.url), ', ' ORDER BY HR.name, R.url)
          FROM host_repo HR JOIN repo R ON R.id = HR.repo_id
         WHERE HR.host_id = H.id) AS repos
  FROM host H
 WHERE H.enabled OR :all
 ORDER BY H.name", ['stale' => STALE_HOURS, 'all' => $all ? 'true' : 'false']);

if (export_format()) {
  export($all ? 'hosts-all' : 'hosts', [
    'name' => 'host', 'os' => 'os', 'version' => 'version', 'enabled' => 'enabled',
    'date_updated' => 'last_checkin_utc', 'stale' => 'stale',
    'packages' => 'packages', 'repos' => 'repositories',
  ], $hosts);
}

$stale = count(array_filter($hosts, fn($r) => $r['stale'] && $r['enabled']));

page_header('Hosts');
?>
<p>
  <?= count($hosts) ?> hosts<?= $all ? ', including disabled ones' : '' ?>;
  <?= $stale === 0 ? 'all have checked in.' : '<span class="stale">' . $stale . ' stale</span>.' ?>
  <a href="index.php<?= $all ? '' : '?all=1' ?>"><?= $all ? 'Hide disabled hosts' : 'Show disabled hosts' ?></a>
</p>
<?= export_links() ?>

<input type="search" class="filter" data-table="hosts" placeholder="Filter hosts" aria-label="Filter hosts">

<table id="hosts" class="sortable">
<thead>
<tr><th>Host</th><th>OS version</th><th>Last check-in</th><th class="num">Packages</th><th>Repositories</th></tr>
</thead>
<tbody>
<?php foreach ($hosts as $r): ?>
<tr<?= $r['enabled'] ? '' : ' class="disabled"' ?>>
  <td><?= host_link($r['name']) ?><?= $r['enabled'] ? '' : ' <span class="tag">disabled</span>' ?></td>
  <td><?= h($r['os'] . ' ' . $r['version']) ?></td>
  <td data-sort="<?= h($r['date_updated']) ?>" title="<?= h(utc($r['date_updated'])) ?>">
    <?= h(age($r['date_updated'])) ?><?= $r['stale'] && $r['enabled'] ? ' <span class="stale">stale</span>' : '' ?>
  </td>
  <td class="num"><?= (int) $r['packages'] ?></td>
  <td><?= h($r['repos']) ?></td>
</tr>
<?php endforeach; ?>
</tbody>
</table>
<?php
page_footer();
