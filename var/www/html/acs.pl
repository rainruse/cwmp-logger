#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;

my $logfile = "/tmp/fcgi.log";
open(my $fh, '>>', $logfile) or die;

my $method   = $ENV{'REQUEST_METHOD' } || '';
my $uri      = $ENV{'DOCUMENT_URI'}    || '';
my $protocol = $ENV{'SERVER_PROTOCOL'} || '';
my $ctype    = $ENV{'CONTENT_TYPE'};
my $clen     = $ENV{'CONTENT_LENGTH'};

# Log Re-constructed request headers and body
print $fh "\n\n$method $uri $protocol\n";
if ($ctype) { print $fh "Content-Type: $ctype\n"; }
if ($clen)  { print $fh "Content-Length: $clen\n"; }
my $body = '';
read(STDIN, $body, $clen || 0);
print $fh "\n$body\n";

my $template = <<'TEMPLATE_EOF';
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<soap_env:Envelope
xmlns:soap_env="http://schemas.xmlsoap.org/soap/envelope/"
xmlns:soap_enc="http://schemas.xmlsoap.org/soap/encoding/"
xmlns:xsd="http://www.w3.org/2001/XMLSchema"
xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
xmlns:cwmp="urn:dslforum-org:cwmp-1-2">
 <soap_env:Header>
  <cwmp:ID soap_env:mustUnderstand="1">{{THE_ID}}</cwmp:ID>
 </soap_env:Header>
 <soap_env:Body>
  <cwmp:InformResponse>
   <MaxEnvelopes>1</MaxEnvelopes>
  </cwmp:InformResponse>
 </soap_env:Body>
</soap_env:Envelope>
TEMPLATE_EOF

sub respond {
    my ($content_type, $body) = @_;
    print $fh "Content-Type: $content_type\r\n";
    print $fh "Content-Length: " . length($body) . "\r\n\r\n";
    print $fh "$body";
    print "Content-Type: $content_type\r\n";
    print "Content-Length: " . length($body) . "\r\n\r\n";
    print "$body";
}

# Handle XML POST. Body should be cwmp soap xml
if ($method eq "POST" && $ctype && $ctype =~ m{\bxml\b}) {
    # wrap with eval to allow for error handling (load_xml can fail)
    eval {
        my $doc = XML::LibXML->load_xml(string => $body);
        my $xpc = XML::LibXML::XPathContext->new($doc);
        $xpc->registerNs('cwmp', 'urn:dslforum-org:cwmp-1-2');
        my ($id) = $xpc->findnodes('//cwmp:ID');
        $id = $id ? $id->textContent : '';
        my ($faultCode) = $xpc->findnodes('//cwmp:Fault/FaultCode');
        my ($faultStr) = $xpc->findnodes('//cwmp:Fault/FaultString');
        if ($faultCode) {
            my $fc = $faultCode ? $faultCode->textContent : '';
            my $fs = $faultStr ? $faultStr->textContent : '';
            print STDERR "FaultCode: $fc, FaultString: $fs";
            respond("text/plain",'');
            exit 0;
        }
        my $eventsPath = '//cwmp:Inform/Event/EventStruct/EventCode';
        my @events = $xpc->findnodes($eventsPath);
        if (@events) {
            my $response = $template;
            $response =~ s/\{\{THE_ID\}\}/$id/g;  # use the proper ID
            respond("text/xml; charset=utf-8", $response);
        } else {
            print STDERR "Did not find any inform EventCode nodes";
            respond("text/plain",'');
            exit 0;
        }
    };
    if ($@) { die "$@"; }
} else {
    respond("text/plain",'');
}
