# cwmp-logger

This is a minimal Auto Configuration Server (ACS) to fetch logs from a CWMP
managed device.

I'm building this to monitor an Ezurio Sentrius RG1xx LoRaWAN gateway for
better visibility into occasional connectivity glitches between the gateway and
its LoRaWAN Network Server (LNS).


## Context: Local First LoRaWAN

This might make more sense if you understand that it's part of a larger goal of
making it easier to do wireless sensor deployments for small scale agriculture
and horticulture.

I'm interested in adapting wireless sensing tech developed for large-scale
corporate networks to be useful at a smaller scale with different assumptions
about infrastructure availability. That means planning for things like how to
keep the sensor monitoring system running when grid power and WAN links are
interrupted (local-first hosting).


## Why DIY CWMP?

The Sentrius RG1xx LoRaWAN gateway has a great RF path, so it's nice to use as
a base station for operating sensors at longer range with higher data rates and
good battery life. But, the firmware is oriented towards managed fleets of the
sort used in telecom infrastructure. I'd use rsyslog logging if I could, but
CWMP appears to be the gateway's supported happy path logging option. So, I'll
go with the flow and use CWMP.

CWMP was developed to manage large fleets of Customer Premises Equipment (CPE)
distributed over wide area networks. A typical ACS might be part of an ISP or
telco billing or admin system with perhaps hundreds or thousands of devices.
All I need is to download logs from one device on a private LAN. GenieACS might
work, but it's very complicated and not the right shape for my purpose. So, I'm
making my own thing.


## Why Perl + FastCGI + Nginx?

Instead of approaching this from the typical modern REST server perspective,
I'm using a retro stack based on Perl FastCGI.

Why? Because...

1. High retro nostalgia entertainment value.

2. CWMP is an older protocol built on SOAP (XML) RPC. Using an older tech stack
   fits. Perl's `XML::LibXML` module has a high-level API that makes it easy to
   extract values from XML documents using XPath style query strings. Modern
   frameworks and libraries tend to focus more on modern serialization formats
   like JSON or protobuf.

3. It's easy to get nginx + fcgiwrap working on Debian and easy to keep them
   current with security updates. No need to worry about getting infected with
   malware from npm or PyPi.

4. Nginx makes it easy to reconfigure network interface bindings, URIs,
   authentication, or TLS without having to edit code.

5. There's no point in over-engineering a debugging tool that will be used with
   one gateway on a private LAN. A modest incomplete solution is fine here.


## Debian Setup

1. Install packages
   ```
   sudo apt install curl socat nginx fcgiwrap libxml-libxml-perl
   ```

2. Configure directory permissions for editing `/var/www/*` with a normal user
   account. The ownership and permissions start as root:root 755. To make it
   work reasonably, we need to add a `wwwedit` group with write permissions,
   change directories to root:wwwedit 775, and set the directory sgid bits so
   that ownership propagates as files and subdirectories are created:
   ```
   sudo groupadd wwwedit
   sudo usermod -aG wwwedit $USER
   exit
   # log back in
   sudo chown root:wwwedit /var/www/html
   sudo chmod 775 /var/www/html
   sudo chmod g+s /var/www/html
   ```

3. Copy the acs.pl perl script to /var/www/html/
   ```
   cd ~
   git clone https://github.com/rainruse/cwmp-logger.git
   cp cwmp-logger/var/www/html/acs.pl /var/www/html/
   ```

4. Copy the nginx site file file to /etc/nginx/sites-available/
   ```
   cd ~/cwmp-logger
   sudo cp etc/nginx/sites-available/my_site /etc/nginx/sites-available/
   ```

6. Enable new site file and disable the default site file
   ```
   sudo ln -s /etc/nginx/sites-available/my_site /etc/nginx/sites-enabled/my_site
   sudo rm /etc/nginx/sites-enabled/default
   sudo nginx -t                # validate config before loading it
   sudo systemctl reload nginx
   ```


## Testing the ACS

Using test data from a file when working on the acs.pl script:

1. Use RG1xx gateway's web admin GUI to set "Remote Management Service" ACS URL
   to point at port 8000 on the debian box.

2. Use `socat` on debian to capture HTTP POST body sent by gateway:
   ```
   socat -d2 TCP-LISTEN:8000,reuseaddr,fork STDOUT
   ```
   Save the POST body XML to a file, perhaps `testsoap.xml`. Initially, the
   CWMP message should be a `cwmp:Inform` with `0 BOOTSTRAP` and `1 BOOT` event
   codes.

3. Test the perl + fcgiwrap + nginx setup by making a POST with `curl` using
   the POST body you captured earlier with socat:
   ```
   $ curl -X POST http://$DEBIAN_BOX_IP/acs \
     -H 'Content-Type: text/xml; charset="utf-8"' --data-binary @testsoap.xml
   ```

To test the acs.pl script against the real gateway, just use the gateway's web
GUI to point Remote Monitoring Service ACS URL at port 80 (vs 8000 for socat).
