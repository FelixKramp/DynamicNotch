#!/usr/bin/perl
# Lädt NotchMediaSources.dylib in /usr/bin/perl, damit MediaRemote antwortet.
#   perl notch-media-sources.pl /pfad/NotchMediaSources.dylib list
#   perl notch-media-sources.pl /pfad/NotchMediaSources.dylib send <bundle-id> <befehl>
use strict;
use warnings;
use DynaLoader;

my ($library, $function, @args) = @ARGV;
die "usage: $0 LIBRARY (list | send BUNDLE_ID COMMAND)\n"
  unless defined $library && defined $function;

if ($function eq "send") {
  die "send needs BUNDLE_ID and COMMAND\n" unless @args == 2;
  $ENV{NMS_BUNDLE_IDENTIFIER} = $args[0];
  $ENV{NMS_COMMAND} = $args[1];
}
elsif ($function ne "list") {
  die "unknown function: $function\n";
}

my $handle = DynaLoader::dl_load_file($library, 0)
  or die "cannot load $library\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "nms_$function")
  or die "symbol nms_$function not found\n";
DynaLoader::dl_install_xsub("main::run", $symbol);
main::run();
