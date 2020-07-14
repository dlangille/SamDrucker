<?php

define('CONF_FILE', '/usr/local/etc/samdrucker.conf');

if (file_exists(CONF_FILE)) {
  require_once(CONF_FILE);
} else {
  syslog(LOG_ERR, CONF_FILE . ' does not exist');
  die(CONF_FILE . ' does not exist');
  exit;
}

json_decode($_REQUEST['packages']);
if (json_last_error() == JSON_ERROR_SYNTAX) {
  # does this need some sanitizing?
  syslog(LOG_ERR, 'invalid json: ' . $_REQUEST['packages']);
  echo 'invalid JSON';
  exit;
}

$dsn = "pgsql:host=$host;port=$port;dbname=$db;user=$user;password=$password;sslmode=require";

try {
  $dbh = new PDO($dsn);

  $dbh->beginTransaction();
  $sql = 'SELECT HostAddPackages(:packages, :client_ip)';

  $stmt = $dbh->prepare($sql);
  # does this need some sanitizing?
  $stmt->bindValue(':packages',  $_REQUEST['packages']);
  $stmt->bindValue(':client_ip', $_SERVER['REMOTE_ADDR']);

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
