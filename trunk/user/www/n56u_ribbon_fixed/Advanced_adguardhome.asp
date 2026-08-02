<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - AdGuardHome</title>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<link rel="stylesheet" type="text/css" href="/govern.css">
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>

<script>
function applySettings() {
    document.form.adg_enable_input.value = document.getElementById('adg_enable_cb').checked ? '1' : '0';
    document.form.adg_redirect_input.value = document.getElementById('adg_redirect_cb').checked ? '1' : '0';
    document.form.action_mode.value = "Apply";
    document.form.submit();
}
</script>
</head>

<body onload="show_menu()">
<div id="TopBanner"></div>
<div id="Loading"></div>

<form method="post" name="form" action="/apply.cgi" target="hidden_frame">
<input type="hidden" name="submit_button" value="Advanced_adguardhome">
<input type="hidden" name="current_page" value="/Advanced_adguardhome.asp">
<input type="hidden" name="sid_list" value="AdguardHomeConf;">
<input type="hidden" name="action_mode" value="">
<input type="hidden" name="action_script" value="restart_adguardhome">
<input type="hidden" name="adg_enable" id="adg_enable_input" value="<% nvram_get("adg_enable"); %>">
<input type="hidden" name="adg_redirect" id="adg_redirect_input" value="<% nvram_get("adg_redirect"); %>">

<table width="98%" cellpadding="4" cellspacing="0" class="FormTitle">
<tr>
  <td>
    <div class="formfontdesc">
      AdGuardHome is a network-wide DNS-based ad blocker. This page only controls
      whether the service runs and whether DNS traffic is redirected to it.
      All filtering rules, upstream DNS servers, and other detailed settings are
      configured in AdGuardHome's own dashboard (link below).
    </div>

    <table width="100%" border="1" cellpadding="4" cellspacing="0" class="FormTable">
      <thead>
        <tr>
          <td colspan="2">AdGuardHome Control</td>
        </tr>
      </thead>

      <tr>
        <th width="30%">Enable AdGuardHome</th>
        <td>
          <input type="checkbox" id="adg_enable_cb" <% nvram_match("adg_enable", "1", "checked"); %>>
        </td>
      </tr>

      <tr>
        <th width="30%">Redirect DNS (port 53) to AdGuardHome</th>
        <td>
          <input type="checkbox" id="adg_redirect_cb" <% nvram_match("adg_redirect", "1", "checked"); %>>
          <br><span style="color:#888;">
            Redirects all LAN DNS traffic on port 53 to AdGuardHome (port 5335).
            Leave this off if you only want to test AdGuardHome without affecting
            the rest of the network yet.
          </span>
        </td>
      </tr>

      <tr>
        <th width="30%">Dashboard</th>
        <td>
          <a href="http://<% nvram_get("lan_ipaddr"); %>:3000/" target="_blank">
            First-time setup wizard (port 3000)
          </a>
          &nbsp;|&nbsp;
          <a href="http://<% nvram_get("lan_ipaddr"); %>:3030/" target="_blank">
            Dashboard (port 3030, after setup is complete)
          </a>
          <br><span style="color:#888;">
            Use the dashboard to configure filter lists, upstream DNS servers,
            client rules, and everything else AdGuardHome supports.
          </span>
        </td>
      </tr>
    </table>

    <div style="margin-top:10px;">
      <input type="button" class="button_gen_long" value="Apply" onclick="applySettings();">
    </div>

  </td>
</tr>
</table>
</form>

<iframe name="hidden_frame" id="hidden_frame" width="0" height="0" frameborder="0"></iframe>

</body>
</html>
