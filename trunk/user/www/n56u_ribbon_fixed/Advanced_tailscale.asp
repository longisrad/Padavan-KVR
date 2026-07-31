<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - Tailscale</title>
<!-- ... -->
<script>
// ...
function fill_status(status_code){
	var stext = "Unknown";
	if (status_code == 0) stext = "Stopped";
	else if (status_code == 1) stext = "Running";
	$("tailscaled_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'success' : 'warning') + '">' + stext + '</span>';
}
function fill_status2(status_code){
	var stext = "Unknown";
	if (status_code == 0) stext = "Stopped";
	else if (status_code == 1) stext = "Running";
	$("tailscale_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'success' : 'warning') + '">' + stext + '</span>';
}
// ...
</script>
</head>
<body onload="initial();" onunLoad="return unload_body();">
<div class="wrapper">
	<!-- ... -->
	<div class="span9">
		<div class="row-fluid">
			<div class="span12">
				<div class="box well grad_colour_dark_blue">
					<h2 class="box_head round_top">Network Tools - Tailscale</h2>
					<div class="round_bottom">
						<ul class="nav nav-tabs">
							<li class="active"><a id="tab_tailscale_cfg" href="#cfg">Settings</a></li>
							<li><a id="tab_tailscale_log" href="#log">Running Log</a></li>
						</ul>
						<div id="wnd_tailscale_cfg">
							<div class="alert alert-info">Tailscale makes it easy to manage access to private resources, quickly SSH into devices on your network, and makes networking simple.
								<div>Current Version: 【<span style="color: #FFFF00;"><% nvram_get_x("", "tailscale_ver"); %></span>】&nbsp;&nbsp;Latest: 【<span style="color: #FD0187;"><% nvram_get_x("", "tailscale_ver_n"); %></span>】</div>
							</div>
							<table class="table">
								<tr><th colspan="4" style="background-color: #756c78;">Running Status</th></tr>
								<tr><th>tailscaled</th><td id="tailscaled_status" colspan="2"></td></tr>
								<tr><th>tailscale</th><td id="tailscale_status" colspan="2"></td></tr>
								<tr><th colspan="4" style="background-color: #756c78;">Configuration</th></tr>
								<tr>
									<th>Enable Tailscale</th>
									<td>
										<select name="tailscale_enable" ...>
											<option value="0">[Disabled]</option>
											<option value="1">[Enabled]</option>
											<option value="2">[Enabled] Custom Parameters</option>
											<option value="3">[Reset] Restore Defaults</option>
										</select>
									</td>
									<td><input class="btn btn-success" type="button" value="Update/Restart" onclick="button_restarttailscale()" /></td>
								</tr>
								<tr id="tailscale_cmd_tr">
									<th>Custom Command</th>
									<td colspan="4"><textarea name="tailscale_cmd" placeholder="up --accept-dns=false ..."></textarea><br><span style="color:#888;">Enter startup command directly without program name.</span></td>
								</tr>
								<tr><th>Accept DNS Settings</th><td><!-- itoggle --></td></tr>
								<tr><th>Accept Routes</th><td><!-- itoggle --> &nbsp;<span style="color:#888;">Accept subnet routes advertised by other nodes.</span></td></tr>
								<tr><th>Local Subnets</th><td colspan="4"><textarea name="tailscale_routes" placeholder="192.168.2.0/24..."></textarea><br><span style="color:#888;">Advertise local subnets (comma separated).</span></td></tr>
								<tr><th>Enable Exit Node</th><td><!-- itoggle --> &nbsp;<span style="color:#888;">Make this device a traffic exit node.</span></td></tr>
								<tr><th>Exit Node Address</th><td><input name="tailscale_exitip" /><br><span style="color:#888;">Specify the exit node IP.</span></td></tr>
								<tr><th>Control Server URL</th><td><input name="tailscale_server" placeholder="https://controlplane.tailscale.com" /><br><span style="color:#888;">Use URL for Headscale if applicable.</span></td></tr>
								<tr><th>Enable SSH Server</th><td><!-- itoggle --></td></tr>
								<tr><th>Outgoing Only (Shields)</th><td><!-- itoggle --> &nbsp;<span style="color:#888;">Block incoming connections from Tailscale network.</span></td></tr>
								<tr><th>Device Name</th><td><input name="tailscale_host" /><br><span style="color:#888;">Identify this device in your Tailnet.</span></td></tr>
								<tr><th>Auth Key</th><td><textarea name="tailscale_key"></textarea><br><span style="color:#888;">Pre-authenticated key for automatic joining.</span></td></tr>
								<tr><th>Custom Binary Path</th><td><textarea name="tailscale_bin"></textarea></td></tr>
								<tr><td colspan="4"><center><input class="btn btn-primary" value="Apply" onclick="applyRule()" /></center></td></tr>
							</table>
						</div>
						<div id="wnd_tailscale_log" style="display:none">
							<textarea rows="21" class="span12" id="textarea"><% nvram_dump("tailscale.log",""); %></textarea>
							<input type="button" onClick="location.reload()" value="Refresh" class="btn btn-primary">
							<input type="button" onClick="clearLog();" value="Clear Log" class="btn btn-info">
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
</div>
</body>
</html>
