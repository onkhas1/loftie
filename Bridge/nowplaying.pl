# Загружает мост Loftie в системный perl и вызывает его (см. nowplaying.m)
use strict;
use DynaLoader;
my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die "load failed";
my $sym = DynaLoader::dl_find_symbol($lib, "loftie_now_playing") or die "symbol not found";
my $sub = DynaLoader::dl_install_xsub("main::loftie_now_playing", $sym);
&$sub();
