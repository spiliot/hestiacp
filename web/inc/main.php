<?php

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

require 'vendor/autoload.php';

session_start();

define('HESTIA_CMD', '/usr/bin/sudo /usr/local/hestia/bin/');
if ($_SESSION['RELEASE_BRANCH'] == 'release' && $_SESSION['DEBUG_MODE'] == 'false') {
    define('JS_LATEST_UPDATE','v=' . $_SESSION['VERSION']);
}else{
    define('JS_LATEST_UPDATE','r=' . time());
}
define('DEFAULT_PHP_VERSION', 'php-' . exec('php -r "echo (float)phpversion();"'));

function destroy_sessions(){
    unset($_SESSION);
    session_unset();
    session_destroy();
}

$i = 0;

// Saving user IPs to the session for preventing session hijacking
$user_combined_ip = $_SERVER['REMOTE_ADDR'];

if (isset($_SERVER['HTTP_CLIENT_IP'])) {
    $user_combined_ip .= '|' . $_SERVER['HTTP_CLIENT_IP'];
}
if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $user_combined_ip .= '|' . $_SERVER['HTTP_X_FORWARDED_FOR'];
}
if (isset($_SERVER['HTTP_FORWARDED_FOR'])) {
    $user_combined_ip .= '|' . $_SERVER['HTTP_FORWARDED_FOR'];
}
if (isset($_SERVER['HTTP_X_FORWARDED'])) {
    $user_combined_ip .= '|' . $_SERVER['HTTP_X_FORWARDED'];
}
if (isset($_SERVER['HTTP_FORWARDED'])) {
    $user_combined_ip .= '|' . $_SERVER['HTTP_FORWARDED'];
}
if (isset($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
      $user_combined_ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
}

if (!isset($_SESSION['user_combined_ip'])) {
    $_SESSION['user_combined_ip'] = $user_combined_ip;
}

// Checking user to use session from the same IP he has been logged in
if ($_SESSION['user_combined_ip'] != $user_combined_ip && $_SERVER['REMOTE_ADDR'] != '127.0.0.1'){
    $v_user = escapeshellarg($_SESSION['user']);
    $v_session_id = escapeshellarg($_SESSION['token']);
    exec(HESTIA_CMD . 'v-log-user-logout ' . $v_user . ' ' . $v_session_id, $output, $return_var);
    destroy_sessions();
    header('Location: /login/');
    exit;
}
// Load Hestia Config directly
    load_hestia_config();

// Check system settings
if ((!isset($_SESSION['VERSION'])) && (!defined('NO_AUTH_REQUIRED'))) {
    destroy_sessions();
    header('Location: /login/');
    exit;
}

// Check user session
if ((!isset($_SESSION['user'])) && (!defined('NO_AUTH_REQUIRED'))) {
    destroy_sessions();
    header('Location: /login/');
    exit;
}

// Generate CSRF Token
if (isset($_SESSION['user'])) {
    if (!isset($_SESSION['token'])){
        $token = bin2hex(file_get_contents('/dev/urandom', false, null, 0, 16));
        $_SESSION['token'] = $token;
    }
}

if (!defined('NO_AUTH_REQUIRED')){
    if (empty($_SESSION['LAST_ACTIVITY']) || empty($_SESSION['INACTIVE_SESSION_TIMEOUT'])){
        destroy_sessions();
        header('Location: /login/');
    } elseif ($_SESSION['INACTIVE_SESSION_TIMEOUT'] * 60 + $_SESSION['LAST_ACTIVITY'] < time()) {
        $v_user = escapeshellarg($_SESSION['user']);
        $v_session_id = escapeshellarg($_SESSION['token']);
        exec(HESTIA_CMD . 'v-log-user-logout ' . $v_user . ' ' . $v_session_id, $output, $return_var);
        destroy_sessions();
        header('Location: /login/');
        exit;
    } else {
        $_SESSION['LAST_ACTIVITY'] = time();
    }
}

if (isset($_SESSION['user'])) {
    $user = $_SESSION['user'];
}

if (isset($_SESSION['look']) && ($_SESSION['userContext'] === 'admin')) {
    $user = $_SESSION['look'];
}

require_once(dirname(__FILE__) . '/i18n.php');

function check_error($return_var) {
    if ( $return_var > 0 ) {
        header('Location: /error/');
        exit;
    }
}

function check_return_code($return_var,$output) {
    if ($return_var != 0) {
        $error = implode('<br>', $output);
        if (empty($error)) $error = sprintf(_('Error code:'), $return_var);
        $_SESSION['error_msg'] = $error;
    }
}

function render_page($user, $TAB, $page) {
    $__template_dir = dirname(__DIR__) . '/templates/';
    $__pages_js_dir = dirname(__DIR__) . '/js/pages/';

    // Header
    include($__template_dir . 'header.html');

    // Panel
    top_panel(empty($_SESSION['look']) ? $_SESSION['user'] : $_SESSION['look'], $TAB);

    // Extract global variables
    // I think those variables should be passed via arguments
    extract($GLOBALS, EXTR_SKIP);

    // Policies controller
    @include_once(dirname(__DIR__) . '/inc/policies.php');

    // Body
    include($__template_dir . 'pages/' . $page . '.html');

    // Including common js files
    @include_once(dirname(__DIR__) . '/templates/includes/end_js.html');
    // Including page specific js file
    if(file_exists($__pages_js_dir . $page . '.js'))
       echo '<script src="/js/pages/' . $page . '.js?' . JS_LATEST_UPDATE . '"></script>';

    // Footer
    include($__template_dir . 'footer.html');
}

function top_panel($user, $TAB) {
    global $panel;
    $command = HESTIA_CMD . 'v-list-user ' . escapeshellarg($user) . " 'json'";
    exec ($command, $output, $return_var);
    if ( $return_var > 0 ) {
        echo '<span style="font-size: 18px;"><b>ERROR: Unable to retrieve account details.</b><br>Please <b><a href="/login/">log in</a></b> again.</span>';
        destroy_sessions();
        header('Location: /login/');
        exit;
    }
    $panel = json_decode(implode('', $output), true);
    unset($output);

    // Log out active sessions for suspended users
    if (($panel[$user]['SUSPENDED'] === 'yes') && ($_SESSION['POLICY_USER_VIEW_SUSPENDED'] !== 'yes')) {
        $_SESSION['error_msg'] = 'You have been logged out. Please log in again.';
        destroy_sessions();
        header('Location: /login/');
    }

    // Reset user permissions if changed while logged in
    if (($panel[$user]['ROLE']) !== ($_SESSION['userContext']) && (!isset($_SESSION['look']))) {
        unset($_SESSION['userContext']);
        $_SESSION['userContext'] = $panel[$user]['ROLE'];
    }

    // Load user's selected theme and do not change it when impersonting user
    if ( (isset($panel[$user]['THEME'])) && (!isset($_SESSION['look']) )) {
        $_SESSION['userTheme'] = $panel[$user]['THEME'];
    }
    
    // Unset userTheme override variable if POLICY_USER_CHANGE_THEME is set to no
    if ($_SESSION['POLICY_USER_CHANGE_THEME'] === 'no') {
        unset($_SESSION['userTheme']);
    }

    // Set preferred sort order
    if (!isset($_SESSION['look'])) {
        $_SESSION['userSortOrder'] = $panel[$user]['PREF_UI_SORT'];
    }
    
    // Set home location URLs
    if (($_SESSION['userContext'] === 'admin') && (!isset($_SESSION['look']))) {
        // Display users list for administrators unless they are impersonating a user account
        $home_url = '/list/user/';
    } else {
        // Set home location URL based on available package features from account
        if ($panel[$user]['WEB_DOMAINS'] != '0') {
            $home_url = '/list/web/';
        } elseif ($panel[$user]['DNS_DOMAINS'] != '0') {
            $home_url = '/list/dns/';
        } elseif ($panel[$user]['MAIL_DOMAINS'] != '0') {
            $home_url = '/list/mail/';
        } elseif ($panel[$user]['DATABASES'] != '0') {
            $home_url = '/list/db/';
        } elseif ($panel[$user]['CRON_JOBS'] != '0') {
            $home_url = '/list/cron/';
        } elseif ($panel[$user]['BACKUPS'] != '0') {
            $home_url = '/list/backups/';
        }
    }

    include(dirname(__FILE__) . '/../templates/includes/panel.html');
}

function translate_date($date){
    $date = strtotime($date);
    return strftime('%d &nbsp;', $date) . _(strftime('%b', $date)) . strftime(' &nbsp;%Y', $date);
}

function humanize_time($usage) {
    if ( $usage > 60 ) {
        $usage = $usage / 60;
        if ( $usage > 24 ) {
             $usage = $usage / 24;
             $usage = number_format($usage);
             return sprintf(ngettext('%d day', '%d days', $usage), $usage);
        } else {
            return sprintf(ngettext('%d hour', '%d hours', $usage), $usage);
        }
    } else {
        return sprintf(ngettext('%d minute', '%d minutes', $usage), $usage);
    }
}

function humanize_usage_size($usage) {
    if ( $usage > 1024 ) {
        $usage = $usage / 1024;
        if ( $usage > 1024 ) {
            $usage = $usage / 1024 ;
            if ( $usage > 1024 ) {
                $usage = $usage / 1024 ;
                $usage = number_format($usage, 2);
            } else {
                $usage = number_format($usage, 2);
            }
        } else {
            $usage = number_format($usage, 2);
        }
    }
    return $usage;
}

function humanize_usage_measure($usage) {
    $measure = 'kb';
    if ( $usage > 1024 ) {
        $usage = $usage / 1024;
        if ( $usage > 1024 ) {
                $usage = $usage / 1024 ;
                $measure = ( $usage > 1024 ) ? 'pb' : 'tb';
        } else {
            $measure = 'gb';
        }
    } else {
        $measure = 'mb';
    }
    return $measure;
}

function get_percentage($used,$total) {
    if (!isset($total)) $total = 0;
    if (!isset($used)) $used = 0;
    if ( $total == 0 ) {
        $percent = 0;
    } else {
        $percent = $used / $total;
        $percent = $percent * 100;
        $percent = number_format($percent, 0, '', '');
        if ( $percent < 0 ) {
            $percent = 0;
        } elseif ( $percent > 100 ) {
            $percent = 100;
        }
    }
    return $percent;
}

function send_email($to, $subject, $mailtext, $from, $from_name, $to_name = '') {
    $mail = new PHPMailer();

    if (isset($_SESSION['USE_SERVER_SMTP']) && $_SESSION['USE_SERVER_SMTP'] == "true") {
        $from = $_SESSION['SERVER_SMTP_ADDR'];

        $mail->IsSMTP();
        $mail->Mailer = "smtp";
        $mail->SMTPDebug  = 0;
        $mail->SMTPAuth   = TRUE;
        $mail->SMTPSecure = $_SESSION['SERVER_SMTP_SECURITY'];
        $mail->Port       = $_SESSION['SERVER_SMTP_PORT'];
        $mail->Host       = $_SESSION['SERVER_SMTP_HOST'];
        $mail->Username   = $_SESSION['SERVER_SMTP_USER'];
        $mail->Password   = $_SESSION['SERVER_SMTP_PASSWD'];
    }

    $mail->IsHTML(true);
    $mail->ClearReplyTos();
    if (empty($to_name)){
        $mail->AddAddress($to);
    }else{
        $mail->AddAddress($to, $to_name);
    }
    $mail->SetFrom($from, $from_name);

    $mail->CharSet = "utf-8";
    $mail->Subject = $subject;
    $content = $mailtext;
    $content = nl2br($content);
    $mail->MsgHTML($content);
    $mail->Send();
}

function list_timezones() {
    foreach(['AKST', 'AKDT', 'PST', 'PDT', 'MST', 'MDT', 'CST', 'CDT', 'EST', 'EDT', 'AST', 'ADT'] as $timezone) {
        $tz = new DateTimeZone($timezone);
        $timezone_offsets[$timezone] = $tz->getOffset(new DateTime);
    }
 
    foreach(DateTimeZone::listIdentifiers() as $timezone) {
        $tz = new DateTimeZone($timezone);
        $timezone_offsets[$timezone] = $tz->getOffset(new DateTime);
    }

    foreach($timezone_offsets as $timezone => $offset) {
        $offset_prefix = $offset < 0 ? '-' : '+';
        $offset_formatted = gmdate( 'H:i', abs($offset) );
        $pretty_offset = "UTC${offset_prefix}${offset_formatted}";
        $t = new DateTimeZone($timezone);
        $c = new DateTime(null, $t);
        $current_time = $c->format('H:i:s');
        $timezone_list[$timezone] = "$timezone [ $current_time ] ${pretty_offset}";
    }
    return $timezone_list;
}

/**
 * A function that tells is it MySQL installed on the system, or it is MariaDB.
 *
 * Explaination:
 * $_SESSION['DB_SYSTEM'] has 'mysql' value even if MariaDB is installed, so you can't figure out is it really MySQL or it's MariaDB.
 * So, this function will make it clear.
 *
 * If MySQL is installed, function will return 'mysql' as a string.
 * If MariaDB is installed, function will return 'mariadb' as a string.
 *
 * Hint: if you want to check if PostgreSQL is installed - check value of $_SESSION['DB_SYSTEM']
 *
 * @return string
 */
function is_it_mysql_or_mariadb() {
    exec (HESTIA_CMD . 'v-list-sys-services json', $output, $return_var);
    $data = json_decode(implode('', $output), true);
    unset($output);
    $mysqltype = 'mysql';
    if (isset($data['mariadb'])) $mysqltype = 'mariadb';
    return $mysqltype;
}

function load_hestia_config() {
    // Check system configuration
    exec (HESTIA_CMD . "v-list-sys-config json", $output, $return_var);
    $data = json_decode(implode('', $output), true);
    $sys_arr = $data['config'];
    foreach ($sys_arr as $key => $value) {
        $_SESSION[$key] = $value;
    }
}

/**
 * Returns the list of all web domains from all users grouped by Backend Template used and owner
 *
 * @return array
 */
function backendtpl_with_webdomains() {
    exec (HESTIA_CMD . 'v-list-users json', $output, $return_var);
    $users = json_decode(implode('', $output), true);
    unset($output);

    $backend_list=[];
    foreach ($users as $user => $user_details) {
        exec (HESTIA_CMD . 'v-list-web-domains '. escapeshellarg($user) . ' json', $output, $return_var);
        $domains = json_decode(implode('', $output), true);
        unset($output);

        foreach ($domains as $domain => $domain_details) {
            if (!empty($domain_details['BACKEND'])) {
                $backend = $domain_details['BACKEND'];
                $backend_list[$backend][$user][] = $domain;
            }
        }
    }
    return $backend_list;
}
/**
 * Check if password is valid
 *
 * @return int; 1 / 0
 */
function validate_password($password){
    return preg_match('/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(.){8,}$/', $password);
}
