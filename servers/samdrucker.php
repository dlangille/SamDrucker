<pre>
<?php

json_decode($_REQUEST['packages']);
if (json_last_error() == JSON_ERROR_SYNTAX) {
  syslog(LOG_ERR, 'invalid json: ' . $_REQUEST['packages']);
  echo 'invalid JSON';
  exit;
}

$host     = 'pg02.int.unixathome.org';
$port     = '5432';
$db       = 'samdrucker';
$user     = 'postie';
$password = '[redacted]';

$dsn = "pgsql:host=$host;port=$port;dbname=$db;user=$user;password=$password;sslmode=require";

try {
  $dbh = new PDO($dsn);

  $dbh->beginTransaction();
  $sql = 'SELECT HostAddPackages(:packages)';

  $stmt = $dbh->prepare($sql);
  $stmt->bindValue(':packages', $_REQUEST['packages']);

  try {
    $stmt->execute();
  }  catch (PDOException $e){
    echo $e->getMessage();
  }

  $dbh->commit();

} catch (PDOException $e){
 // report error message
 syslog(LOG_ERR, $e->getMessage());
}

?>

</pre>
