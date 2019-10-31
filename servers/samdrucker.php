<pre>
<?php

#phpinfo();

#echo urldecode($_SERVER['package']);

echo 'Incoming data is:<br><br>';

echo $_REQUEST['packages'];

$db = pg_connect("dbname=samdrucker host=pg02.example.org user=postie password=password sslmode=require");

echo '<br><br>SQL is:<br><br>';

$sql = 'SELECT HostAddPackages(' . pg_escape_literal($_REQUEST['packages']) . ')';

echo $sql;

$result = pg_exec($db, $sql);

echo $result;

pg_close($db);

?>

</pre>
