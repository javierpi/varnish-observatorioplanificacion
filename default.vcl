## Varnish para sitios de comunidades 
##################
#  ver 1.01
#  
#
##################


import std; 
include "/etc/varnish/deny_admin.vcl";

acl purge {
		"10.0.0.0"/16; ## cepal santiago completa
		 "localhost";
		 "127.0.0.1";
}


# Default backend definition.  Set this to point to your content
# server.
#
# include "drupal_director.vcl";
backend drupal
{
    .host = "10.0.9.192";
    .port = "80";
    .max_connections = 200;
   #.connect_timeout = 10s;
   #.first_byte_timeout = 120s;
   #.between_bytes_timeout = 120s;
   .connect_timeout = 3.5s;
   .first_byte_timeout = 60s;
   .between_bytes_timeout = 60s;
}



# Respond to incoming requests.
sub vcl_recv {

	######
	# CONF-359 
	#
	
	if (req.url ~ "PURGE" || req.request == "PURGE") {
		if (client.ip ~ purge) {
			# =============================================
			# Se pasa solicitud de Purge desde URL a Request 
			set req.request = "PURGE";
			# Se quita PURGE de la URL
			set req.url = regsub(req.url, "\/PURGE", "");
			# =============================================
			return(lookup);
		}else{
			error 404 "Not allowed";
		}
	}
	
	######
	
	
		
	set req.backend = drupal;

	#  Use anonymous, cached pages if all backends are down.
	if (!req.backend.healthy) {
		#unset req.http.Cookie;
		error 755 "";
	}
	


	# Allow the backend to serve up stale content if it is responding slowly.
	set req.grace = 600s;

	# Client IP is forwarded (instead of the) además del proxy 
	if (req.restarts == 0) {
		if (req.http.x-forwarded-for) {
			set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
		} else {
			set req.http.X-Forwarded-For = client.ip;
		}
	}
	 
	
	call deny_admin_drupal;
		 
	# Always cache the following file types for all users. This list of extensions
	# appears twice, once here and again in vcl_fetch so make sure you edit both
	# and keep them equal.
	if (req.url ~ "(?i)\.(pdf|asc|dat|txt|doc|docx|xls|ppt|tgz|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
		unset req.http.Cookie;
	}
	 
	# Remove all cookies that Drupal doesn't need to know about. We explicitly
	# list the ones that Drupal does need, the SESS and NO_CACHE. If, after
	# running this code we find that either of these two cookies remains, we
	# will pass as the page cannot be cached.
	if (req.http.Cookie) {
		set req.http.Cookie = ";" + req.http.Cookie;
		set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");   
		set req.http.Cookie = regsuball(req.http.Cookie, ";(S{1,2}ESS[a-z0-9]+|NO_CACHE|context_breakpoints)=", "; \1=");
		set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
		set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

		if (req.http.Cookie == "") {
			# If there are no remaining cookies, remove the cookie header. If there
			# aren't any cookie headers, Varnish's default behavior will be to cache
			# the page.
			unset req.http.Cookie;
		} else {
			# If there is any cookies left (a session or NO_CACHE cookie), do not
			# cache the page. Pass it on to Apache directly.
			return (pass);
		}
	}
}

sub vcl_hit { 
	if (req.request == "PURGE") {
        purge;
        error 204 "Purged";
    }
}

sub vcl_miss{
	if (req.request == "PURGE") {
        purge;
        error 204 "Purged (Not in cache)";
    }
 }
 
# Set a header to track a cache HIT/MISS.
sub vcl_deliver {
	if (obj.hits > 0) {
		set resp.http.X-Varnish-Cache = "HIT";
	} else {
		set resp.http.X-Varnish-Cache = "MISS";
	}
}
 
# Code determining what to do when serving items from the Apache servers.
# beresp == Back-end response from the web server.
sub vcl_fetch {
	# We need this to cache 404s, 301s, 500s. Otherwise, depending on backend but
	# definitely in Drupal's case these responses are not cacheable by default.
	if (beresp.status == 404 || beresp.status == 301 || beresp.status == 500) {
		set beresp.ttl = 10m;
	}

	# Don't allow static files to set cookies.
	# (?i) denotes case insensitive in PCRE (perl compatible regular expressions).
	# This list of extensions appears twice, once here and again in vcl_recv so
	# make sure you edit both and keep them equal.
	if (req.url ~ "(?i)\.(pdf|asc|dat|txt|doc|docx|xls|ppt|tgz|csv|png|gif|jpeg|jpg|ico|swf|ccs|js)(\?.*)?$") {
		unset beresp.http.set-cookie;
	}

	# Allow items to be stale if needed.
	set beresp.grace = 600s;
}
 
# In the event of an error, show friendlier messages.
sub vcl_error {

	

	## Acceso denegado. Han enviado URL que se ha programado no entregar.
	if (obj.status == 752) {
		# Acceso denegado  403;
		#call error_403;
		# Se cambia para no indicar que existe y está prohibido
		set obj.status = 404;
		#set obj.http.Content-Type = "text/html; charset=utf-8";
        #synthetic std.fileread("/etc/varnish/error404.html");
		 
		set obj.http.Content-Type = "text/html; charset=utf-8";
		synthetic {"
			<html>
			<head>
			  <title>404 Page not found</title>
			  <style>
				body { background: #303030; text-align: center; color: white; }
				#page { border: 1px solid #CCC; width: 500px; margin: 100px auto 0; padding: 30px; background: #323232; }
				a, a:link, a:visited { color: #CCC; }
				.error { color: #222; }
			  </style>
			</head>
			<body onload="setTimeout(function() { window.location = '/es' }, 5)">
			  <div id="page">
				<h1 class="title">Not found</h1>
				<p>.</p>
				<p> <a href="/">homepage</a> in 5 seconds.</p>
				<div class="error">(Error "} + obj.status + " " + obj.response + {")</div>
			  </div>
			</body>
			</html>
		"};
        return(deliver);
	}
	
	return (deliver);
}
