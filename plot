#! /usr/bin/perl

# add datum
# OSM mode
# auto-choose chart, maybe use multiple charts
# contacts (bearing-only, range)
# contacts:
#   U23:
#     KRI: bearing
#     KRI: fix
# feed into detected/history? ("detectors"?)

use strict;
use warnings FATAL => 'all';

use Getopt::Std;
use YAML::XS;
use Imager;
use Geo::Ellipsoid;
use List::Util qw(max min);
use Math::Trig qw(:pi deg2rad rad2deg tan);
use HTML::Template;
use POSIX qw(strftime);

my %o=(d => 0,h => 30,z => 'a');
getopts('d:h:s:z:',\%o);
# -d 1 include depth bands
# -d 2 shade rather than label depth bands
# -h N limit history to N minutes
# -s side name to plot
# -z zoom scale

my $geo=Geo::Ellipsoid->new(units=>'degrees');
my $nm=1852;
my $yard=0.9144;
my $c30=cos(deg2rad(30));
my $s30=sin(deg2rad(30));
my $c60=$s30;
my $s60=$c30;
my $fn=Imager::Font->new(file => '/usr/share/fonts/truetype/ttf-liberation/LiberationSans-Regular.ttf',
                         size => 10,
                         utf8 => 1);
open DEPTH,'<','map/ETOPO1/etopo1_bed_g_f4.flt';
binmode DEPTH;
umask 0022;

my $y=yaml_load_file($ARGV[0]);
$ENV{TZ}=$y->{general}{timezone} || 'GMT';
(my $stub=$ARGV[0]) =~ s/\.yaml$//;
my $outpath='.';
if ($stub =~ /(.*)\/([^\/]+)/) {
  $outpath=$1;
  $stub=$2;
}
my %cvt=(plotmode => 'plain');
if (exists $y->{general}{chart}) { # maybe "osm" later
  $cvt{plotmode}='chart';
}
if ($cvt{plotmode} eq 'chart') {
  my $yd=yaml_load_file('datum.yaml')->{$y->{general}{chart}};
  my @ix=split ' ',$yd->{latline};
  ($cvt{xcen},$cvt{ycen},my $rad)=circumCircleCenter(
    map {$yd->{$_}{x},$yd->{$_}{y}}
      @ix
        );

  my @iy=split ' ',$yd->{lonline};
  my $lonlen=Length(
    map {$yd->{$_}{x},$yd->{$_}{y}}
      @iy
        );

  foreach my $k (map {"par$_"} (1,2)) {
    if ($yd->{$k} =~ /(-?)(\d+)-(\d+)(?:-(\d+))?/) {
      my $base=$2+$3/60;
      if (defined $4) {
        $base+=$4/3600;
      }
      if ($1 eq '-') {
        $base-=$base;
      }
      $yd->{$k}=$base;
    }
  }
  $cvt{reflat}=($yd->{par1}+$yd->{par2})/2;

  # values to translate radius from degrees to pixel count
# note, these are the accurate values, but they look worse on the map!
#  $cvt{rm}=$lonlen/(tan(deg2rad($yd->{$iy[1]}{a}-$cvt{reflat}))-tan(deg2rad($yd->{$iy[0]}{a}-$cvt{reflat})));
#  $cvt{rc}=$rad-(tan(deg2rad($yd->{$iy[0]}{a}-$cvt{reflat}))*$cvt{rm});
  $cvt{rm}=$lonlen/($yd->{$iy[1]}{a}-$yd->{$iy[0]}{a});
  $cvt{rc}=$rad-($yd->{$iy[0]}{a}*$cvt{rm});


  my @angle=map {atan2($yd->{$ix[$_]}{y}-$cvt{ycen},$yd->{$ix[$_]}{x}-$cvt{xcen})} (0,2);
  $cvt{thm}=($angle[1]-$angle[0])/($yd->{$ix[2]}{o}-$yd->{$ix[0]}{o});
  $cvt{thc}=$angle[0]-($yd->{$ix[0]}{o}*$cvt{thm});
}

# load chart
#my $imgbase=Imager->new(file => "map/$y->{general}{chart}.jpg");
#
#my $overlay=Imager->new(xsize => $imgbase->getwidth,
#                        ysize => $imgbase->getheight,
#                        channels => 4);

$y->{general}{side}{all}{keyword}='all';
my @sides;
foreach my $sn (keys %{$y->{units}}) {
  if ($o{s}) {
    if (lc($o{s}) eq lc($sn)) {
      push @sides,$sn;
    }
  } else {
    push @sides,$sn;
  }
}
if ($o{s} && $o{s} eq 'all') {
  push @sides,'all';
}

foreach my $sidename (@sides) {
  my @boundsll;
  my %info;
  foreach my $pass (1..(($cvt{plotmode} eq 'chart')?3:2)) {
    # pass 1: calculation only
    # pass 2: active map
    # pass 3: full map
    my $img;
    my $ovl;
    my $black=Imager::Color->new('black');
    if ($pass>1) {
      if ($cvt{plotmode} eq 'chart') {
        $img=Imager->new(file => "map/$y->{general}{chart}.jpg");
        if ($pass==2) {
          if (exists $info{crop}) {
            $cvt{crop}=$info{crop};
            $img=$img->crop(%{$cvt{crop}});
          }
          if (exists $info{scale}) {
            $cvt{scale}=$info{scale};
            $img=$img->scale(scalefactor => $cvt{scale});
          }
        }
      } elsif ($cvt{plotmode} eq 'plain') {
        $img=Imager->new(xsize => $cvt{crop}{width},
                         ysize => $cvt{crop}{height});
        my $blue=Imager::Color->new(187, 206, 236);
        $img->box(color => $blue, filled => 1);
        my @bll;
        foreach my $y (0,$cvt{crop}{height}*$cvt{scale}/2,$cvt{crop}{height}*$cvt{scale}) {
          foreach my $x (0,$cvt{crop}{width}*$cvt{scale}/2,$cvt{crop}{width}*$cvt{scale}) {
            push @bll,[xy2ll($x,$y)];
          }
        }
        my $mlatmin=min(map {$bll[$_][0]} (0..$#bll));
        my $mlatmax=max(map {$bll[$_][0]} (0..$#bll));
        my $mlonmin=min(map {$bll[$_][1]} (0..$#bll));
        my $mlonmax=max(map {$bll[$_][1]} (0..$#bll));
        for (my $lat=int($mlatmin*2)/2;$lat<=$mlatmax;$lat+=0.5) {
          my @poly;
          for (my $xlon=int($mlonmin*60);$xlon<=$mlonmax*60+1;$xlon++) {
            my $lon=$xlon/60;
            push @poly,[ll2xy($lat,$lon)];
            my @bound;
            if ($xlon%30==0) {
              next;
            } elsif ($xlon%10==0) {
              @bound=(-2/3,2/3);
            } elsif ($xlon%5==0) {
              @bound=(0,2/3);
            } else {
              @bound=(0,1/3);
            }
            my @a=ll2xy($lat+$bound[0]/60,$lon);
            my @b=ll2xy($lat+$bound[1]/60,$lon);
            $img->line(x1 => $a[0],y1 => $a[1],
                       x2 => $b[0],y2 => $b[1],
                       colour => $black);
          }
          $img->polyline(points => \@poly,
                         color => $black);
        }
        for (my $lon=int($mlonmin*2)/2;$lon<=$mlonmax;$lon+=0.5) {
          my @poly;
          for (my $xlat=int($mlatmin*60);$xlat<=$mlatmax*60+1;$xlat++) {
            my $lat=$xlat/60;
            push @poly,[ll2xy($lat,$lon)];
            my @bound;
            if ($xlat%30==0) {
              next;
            } elsif ($xlat%10==0) {
              @bound=(-2/3,2/3);
            } elsif ($xlat%5==0) {
              @bound=(0,2/3);
            } else {
              @bound=(0,1/3);
            }
            my @a=ll2xy($lat,$lon+$bound[0]/60);
            my @b=ll2xy($lat,$lon+$bound[1]/60);
            $img->line(x1 => $a[0],y1 => $a[1],
                       x2 => $b[0],y2 => $b[1],
                       colour => $black);
          }
          $img->polyline(points => \@poly,
                         color => $black);
        }
        for (my $lat=int($mlatmin);$lat<=$mlatmax;$lat++) {
          my $displat=abs($lat);
          if ($lat>0) {
            $displat.='N';
          } else {
            $displat.='S';
          }
          for (my $lon=int($mlonmin);$lon<=$mlonmax;$lon++) {
            my $displon=abs($lon);
            if ($lon>0) {
              $displon.='E';
            } else {
              $displon.='W';
            }
            my @xy=ll2xy($lat,$lon);
            $img->align_string(x => $xy[0]-3,
                               y => $xy[1]-3,
                               valign => 'bottom',
                               halign => 'right',
                               font => $fn,
                               size => 20,
                               color => $black,
                               string => $displat);
            $img->align_string(x => $xy[0]+3,
                               y => $xy[1]+3,
                               valign => 'top',
                               halign => 'left',
                               font => $fn,
                               size => 20,
                               color => $black,
                               string => $displon);
          }
        }
      }
      $ovl=Imager->new(xsize => $img->getwidth,
                       ysize => $img->getheight,
                       channels => 4);
      # draw general drawing objects
      if (exists $y->{general}{draw}) {
        foreach my $o (@{$y->{general}{draw}}) {
          gendraw($img,$ovl,$o);
        }
      }
    }
    foreach my $sideplot (keys %{$y->{units}}) {
      my $friendly=$sidename eq 'all' || ($sideplot eq $sidename);
      foreach my $unith (@{$y->{units}{$sideplot}}) {
        my $unitname=(keys %{$unith})[0];
        my $unit=$unith->{$unitname};
        $unit->{colour} ||= $y->{general}{side}{$sideplot}{colour};
        my $style=$unit->{style} || $y->{general}{side}{$sideplot}{style};
        my $plothistory=0;
        (my $id=$unitname) =~ s/[^A-Za-z]+/_/g;
        $unit->{label}=($friendly?undef:$unit->{foreignshort}) || $unit->{short} || substr(uc($unitname),0,3);
        $unit->{name}=$unitname;
        if ($friendly || exists $unit->{detected}) {
          $plothistory=1;
          my @ll=locparse($unit);
          if ($pass==1) {
            push @boundsll,\@ll;
          } else {
            my @xy=ll2xy(@ll);
            plot(img => $img,
                 x => $xy[0],
                 y => $xy[1],
                 unit => $unit,
                 style => $style,
                 colour => $unit->{colour},
                 scale => 10);
            if ($friendly && exists $unit->{draw}) {
              my @uc;
              if (ref $unit->{draw} eq 'ARRAY') {
                @uc=@{$unit->{draw}};
              } else {
                @uc=($unit->{draw});
              }
              foreach my $uc (@uc) {
                if (!exists $uc->{loc} && !exists $uc->{lat} && !exists $uc->{lon}) {
                  foreach my $mode (qw(lat lon loc)) {
                    if (exists $unit->{$mode}) {
                      $uc->{$mode}=$unit->{$mode};
                    }
                  }
                }
                foreach my $mode (qw(colour alpha)) {
                  if (!exists $uc->{$mode} && exists $unit->{$mode}) {
                    $uc->{$mode}=$unit->{$mode};
                  }
                }
                gendraw($img,$ovl,$uc);
              }
            }
          }
        }
        if ($plothistory==0 && exists $unit->{history}) {
          foreach (@{$unit->{history}}) {
            if (exists $_->{detected}) {
              $plothistory=1;
              last;
            }
          }
        }
        if ($plothistory>0 && exists $unit->{history}) {
          if ($friendly) {
            $plothistory=2;
          }
          my @line;
          my @r=@{$unit->{history}};
          push @r,$unit;
          my $plotted=[];
          my $threshold=$y->{general}{time}-60*$o{h};
          foreach my $ri (0..$#r) {
            if ($plothistory==2 || exists $r[$ri]{detected}) {
              if (exists $r[$ri]{time} && $r[$ri]{time}<$threshold) {
                next;
              }
              my @llx=locparse($r[$ri]);
              if ($pass==1) {
                push @boundsll,\@llx;
              } else {
                my @xy=ll2xy(@llx);
                if ($ri<$#r) {
                  my $tm=timeformat($r[$ri]{time});
                  if ($r[$ri]{speed} >= 240 ||
                        ($r[$ri]{speed} >= 60 && length($tm)<5) ||
                          ($r[$ri]{speed} >= 12 &&
                             length($tm)==4 &&
                               substr($tm,2,2)/3 == int(substr($tm,2,2)/3)) ||
                                 (length($tm)==4 &&
                                    substr($tm,2,2)/12 == int(substr($tm,2,2)/12))) {
                    $img->circle(color => $unit->{colour},
                                 r => 2,
                                 x => $xy[0],
                                 y => $xy[1]);
                    $img->align_string(x => $xy[0],
                                       y => $xy[1]-3,
                                       valign => 'bottom',
                                       halign => 'center',
                                       font => $fn,
                                       color => $unit->{colour},
                                       string => $tm);
                  }
                }
                push @line,\@xy;
                $plotted=\@xy;
              }
            }
          }
          if ($pass>1) {
            $img->polyline(points => \@line,
                           color => $unit->{colour});
            if ($plothistory==1 && $plotted && !exists $unit->{detected}) {
              $img->align_string(x => $plotted->[0],
                                 y => $plotted->[1]+3,
                                 valign => 'top',
                                 halign => 'center',
                                 font => $fn,
                                 color => $unit->{colour},
                                 string => $unit->{label});
            }
          }
        }
      }
    }

    if ($pass==1) {
      my @max;
      my @min;
      if (exists $y->{general}{bounds}) {
        foreach my $item (@{$y->{general}{bounds}}) {
          push @boundsll,[locparse($item)];
        }
      }
      foreach my $axis (0,1) {
        my @list=map {$_->[$axis]} @boundsll;
        $max[$axis]=max(@list);
        $min[$axis]=min(@list);
      }
      if ($cvt{plotmode} eq 'chart') {
        my @bll;
        foreach my $lat ($min[0],($min[0]+$max[0])/2,$max[0]) {
          foreach my $lon ($min[1],($min[1]+$max[1])/2,$max[1]) {
            push @bll,[ll2xy($lat,$lon)];
          }
        }
        my $xmin=min(map{$_->[0]} @bll)-20;
        my $xsiz=max(map{$_->[0]} @bll)-$xmin+40;
        my $ymin=min(map{$_->[1]} @bll)-20;
        my $ysiz=max(map{$_->[1]} @bll)-$ymin+40;
        $info{crop}={left => $xmin,top => $ymin,width => $xsiz,height => $ysiz};
        if ($o{z} eq 'a') {
          $info{scale}=max(1,int(800/$xsiz));
        } else {
          $info{scale}=$o{z} || 1;
        }
      } elsif ($cvt{plotmode} eq 'plain') {
        my @c=(max(0.01,$max[0]-$min[0]),max(0.01,$max[1]-$min[1]));
        (my $a,my $b)=$geo->displacement(@c,$c[0]+.1,$c[1]+.1);
        my $ratio=$b/$a;
        $info{crop}={left => 0, top => 0, width => 800};
        $info{xscale}=min($info{crop}{width}/$c[1],$info{crop}{width}/$c[0]/$ratio)*0.9;
        $info{yscale}=$ratio*$info{xscale};
        $info{xoffset}=$info{crop}{width}/2-($max[1]+$min[1])/2*$info{xscale};
        $info{crop}{height}=int($info{crop}{width}*$ratio);
        $info{yscale}=-$ratio*$info{xscale};
        $info{yoffset}=$info{crop}{height}/2-($max[0]+$min[0])/2*$info{yscale};
        $info{scale}=1;
        map {$cvt{$_}=$info{$_}} qw(xscale yscale scale xoffset yoffset crop);
      }
    } else {
      $img->rubthrough(src => $ovl);
      if ($pass==2) {
        if ($o{d}) {
          my @bll;
          foreach my $y (0,$cvt{crop}{height}*$cvt{scale}/2,$cvt{crop}{height}*$cvt{scale}) {
            foreach my $x (0,$cvt{crop}{width}*$cvt{scale}/2,$cvt{crop}{width}*$cvt{scale}) {
              push @bll,[xy2ll($x,$y)];
            }
          }
          my $mlatmin=int(60*min(map {$bll[$_][0]} (0..$#bll)));
          my $mlatmax=int(60*max(map {$bll[$_][0]} (0..$#bll))+1);
          my $mlonmin=int(60*min(map {$bll[$_][1]} (0..$#bll)));
          my $mlonmax=int(60*max(map {$bll[$_][1]} (0..$#bll))+1);
          my $depthovl=Imager->new(xsize => $img->getwidth,
                                   ysize => $img->getheight,
                                   channels => 4);
          my %dmap;
          my %sb;
          if ($o{d}==2) {
            %sb=(x => 0,
                 'S' => 'grey50' ,
                 'I' => 'grey30' ,
                 'D' => 'grey10',
                 'V' => 'black',
                   );
            foreach my $m (keys %sb) {
              if ($sb{$m}) {
                my @oc=Imager::Color->new($sb{$m})->rgba;
                $oc[3]=128;
                $sb{$m}=Imager::Color->new(@oc);
              }
            }
          }
          foreach my $lat ($mlatmin..$mlatmax) {
            foreach my $lon ($mlonmin..$mlonmax) {
              if ($o{d}==2) {
                my $c=$sb{shadeband(getdepth($lat,$lon))};
                if ($c) {
                  my @points=map {[ll2xy(@{$_})]}
                    (
                      [($lat-0.5)/60,($lon-0.5)/60],
                      [($lat-0.5)/60,($lon+0.5)/60],
                      [($lat+0.5)/60,($lon+0.5)/60],
                      [($lat+0.5)/60,($lon-0.5)/60],
                      [($lat-0.5)/60,($lon-0.5)/60],
                        );
                  $depthovl->polygon(points => \@points,color => $c);
                }
              } else {
                $dmap{$lat}{$lon}=mapband(getdepth($lat,$lon));
              }
            }
          }
          unless ($o{d}==2) {
            my @plot;
            my %dd;
            foreach my $lat ($mlatmin..$mlatmax) {
              foreach my $lon ($mlonmin..$mlonmax) {
                my $np=0;
                if ($lat<$mlatmax && $dmap{$lat}{$lon} ne $dmap{$lat+1}{$lon}) {
                  push @plot,[[ll2xy(($lat+0.5)/60,($lon-0.5)/60)],
                              [ll2xy(($lat+0.5)/60,($lon+0.5)/60)],
                                ];
                  $dd{$lat}{$lon}=$dd{$lat+1}{$lon}=1;
                }
                if ($lon<$mlonmax && $dmap{$lat}{$lon} ne $dmap{$lat}{$lon+1}) {
                  push @plot,[[ll2xy(($lat-0.5)/60,($lon+0.5)/60)],
                              [ll2xy(($lat+0.5)/60,($lon+0.5)/60)],
                                ];
                  $dd{$lat}{$lon}=$dd{$lat}{$lon+1}=1;
                }
              }
            }
            foreach my $lat ($mlatmin..$mlatmax) {
              foreach my $lon ($mlonmin..$mlonmax) {
                if (exists $dd{$lat}{$lon}) {
                  my @xy=ll2xy($lat/60,$lon/60);
                  $depthovl->align_string(x => $xy[0],
                                          y => $xy[1],
                                          valign => 'center',
                                          halign => 'center',
                                          font => $fn,
                                          color => $black,
                                          string => $dmap{$lat}{$lon});
                }
              }
            }
            foreach my $pair (@plot) {
              $depthovl->polyline(points => $pair,
                                  color => $black);
            }
          }
          $img->rubthrough(src => $depthovl);
        }                       # end depth overlay
        my @scalestart=xy2ll(10,$info{crop}{height}*$info{scale}-25);
        my @scaleend=xy2ll($info{crop}{width}-10,$info{crop}{height}*$info{scale}-25);
        {
          my $r=$geo->range(@scalestart,@scaleend)/$nm;
          my $base=10**(int(log($r)/log(10)));
          my $sub=$base/5;
          if ($base*5 < $r) {
            $base*=5;
            $sub=$base/5;
          } elsif ($base*2 < $r) {
            $base*=2;
            $sub=$base/4;
          }
          my @pt;
          for (my $sc=0;$sc<=$base;$sc+=$sub) {
            push @pt,[ll2xy($geo->at(@scalestart,$sc*$nm,90))];
          }
          $img->align_string(x => $pt[0][0],
                             y => $pt[0][1]-2,
                             valign => 'bottom',
                             halign => 'left',
                             font => $fn,
                             color => $black,
                             string => "nautical mile");
          foreach my $ix (0..$#pt) {
            $img->align_string(x => $pt[$ix][0],
                               y => $pt[$ix][1]+7,
                               valign => 'top',
                               halign => 'center',
                               font => $fn,
                               color => $black,
                               string => $ix*$sub);
          }
          foreach my $ix (0..$#pt-1) {
            my @points=($pt[$ix],
                        $pt[$ix+1],
                        [$pt[$ix+1][0],$pt[$ix+1][1]+5],
                        [$pt[$ix][0],$pt[$ix][1]+5],
                          );
            if ($ix%2==0) {
              $img->polygon(points => \@points,color => $black);
            } else {
              push @points,$points[0];
              $img->polyline(points => \@points,color => $black);
            }
          }
        }
        delete $cvt{crop};
        delete $cvt{scale};
        $img->write(file => join('.',"$outpath/$stub",$y->{general}{side}{$sidename}{keyword},'jpg'));
      }                         # end pass 2 only
      if ($pass==3) {           # highlight active area
        foreach my $delta (1..10) {
          $img->box(color => $black,
                    xmin => $info{crop}{left}-$delta,
                    ymin => $info{crop}{top}-$delta,
                    xmax => $info{crop}{left}+$info{crop}{width}+$delta,
                    ymax => $info{crop}{top}+$info{crop}{height}+$delta);
        }
        $img->write(file => join('.',"$outpath/$stub",$y->{general}{side}{$sidename}{keyword},'full.jpg'));
      }
    }                           # end pass 2-3 only
  }
}

my $tsrc=[<DATA>];

foreach my $fromside (@sides) {
  my $tmpl=HTML::Template->new(arrayref => $tsrc,
                               die_on_bad_params => 0);
  my @rt;
  my @eu;
  my @eut;
  foreach my $toside (sort keys %{$y->{units}}) {
    if ($fromside ne $toside || $fromside eq 'all') {
      foreach my $tounit (@{$y->{units}{$toside}}) {
        my $eu0=(keys %{$tounit})[0];
        my $eu1=$tounit->{$eu0};
        if (exists $eu1->{detected} || $fromside eq 'all') {
          my $height='';
          if (exists $eu1->{depth}) {
            $height=abs($eu1->{depth}).' ['.unitband(-abs($eu1->{depth})).'] / '.abs(getdepth(map {int($_*60)} locparse($eu1)));
          } elsif (exists $eu1->{altitude}) {
            $height=$eu1->{altitude}.' ['.unitband($eu1->{altitude}).'] / '.max(0,getdepth(map {int($_*60)} locparse($eu1)));
          }
          push @eu,$tounit;
          my $id;
          if ($fromside eq 'all' && exists $eu1->{foreignshort} && $eu1->{label} ne $eu1->{foreignshort}) {
            $id=join('/',$eu1->{label},$eu1->{foreignshort});
          } else {
            $id=$eu1->{foreignshort} || $eu1->{label};
          }
          push @eut,{id => $id,
                     name => $eu0,
                     height => $height,
                     %{$eu1}};
        }
      }
    }
  }
  my @fu;
  if ($fromside eq 'all') {
    foreach my $fs (sort keys %{$y->{units}}) {
      push @fu,@{$y->{units}{$fs}};
    }
  } else {
    @fu=@{$y->{units}{$fromside}};
  }
  foreach my $fromunit (@fu) {
    my $fu0=(keys %{$fromunit})[0];
    my $fu1=$fromunit->{$fu0};
    $fu1->{label}=$fu1->{short} || substr(uc($fu0),0,3);
    my %line=(id => $fu1->{label},
              name => $fu0,
              speed => $fu1->{speed} || 0,
              course => $fu1->{course},
                );
    if (exists $fu1->{depth}) {
      $line{height}=abs($fu1->{depth}).' ['.unitband(-abs($fu1->{depth})).'] / '.abs(getdepth(map {int($_*60)} locparse($fu1)));
    } elsif (exists $fu1->{altitude}) {
      $line{height}=$fu1->{altitude}.' ['.unitband($fu1->{altitude}).'] / '.max(0,getdepth(map {int($_*60)} locparse($fu1)));
    }
    my @row;
    foreach my $enemy (@eu) {
      my $eu0=(keys %{$enemy})[0];
      my $eu1=$enemy->{$eu0};
      if ($fu0 eq $eu0) {
        push @row,{range => '',bearing => ''};
      } else {
        my ($range,$bearing)=$geo->to(
          locparse($fu1),
          locparse($eu1),
            );
        $range/=$nm;
        my $relative=$bearing-$fu1->{course};
        while ($relative<-180) {
          $relative+=360;
        }
        while ($relative>180) {
          $relative-=360;
        }
        my $relcol;
        if ($relative>0) {
          $relative="s".int($relative+0.5);
          $relcol='#00c000';
        } else {
          $relative="p".int(abs($relative)+0.5);
          $relcol='#c00000';
        }
        push @row,{range => sprintf('%.1f',$range),
                   bearing => int($bearing+0.5),
                   relative => $relative,
                   relcol => $relcol};
      }
    }
    $line{enemyunit}=\@row;
    push @rt,\%line;
  }
  $tmpl->param(enemyunit => \@eut,
               rangetable => \@rt,
               side => $fromside,
               keyword => $y->{general}{side}{$fromside}{keyword},
               stub => $stub,
               full => ($cvt{plotmode} eq 'chart'));
  open OUT,'>:encoding(UTF-8)',"$outpath/$stub.$y->{general}{side}{$fromside}{keyword}.html";
  print OUT $tmpl->output;
  close OUT;
}

close DEPTH;

sub ll2xy {
  my ($lat,$lon)=@_;
  my ($x,$y);
  if ($cvt{plotmode} eq 'chart') {
    my $theta=$cvt{thm}*$lon+$cvt{thc};
    # again, should be more accurate, looks worse!
    # my $r=$cvt{rm}*tan(deg2rad($lat-$cvt{reflat}))+$cvt{rc};
    my $r=$cvt{rm}*$lat+$cvt{rc};
    $x=$r*cos($theta)+$cvt{xcen};
    $y=$r*sin($theta)+$cvt{ycen};
  } elsif ($cvt{plotmode} eq 'plain') {
    $x=$lon*$cvt{xscale}+$cvt{xoffset};
    $y=$lat*$cvt{yscale}+$cvt{yoffset};
  }
  if (exists $cvt{crop}) {
    $x-=$cvt{crop}{left};
    $y-=$cvt{crop}{top};
  }
  if (exists $cvt{scale}) {
    $x*=$cvt{scale};
    $y*=$cvt{scale};
  }
  return ($x,$y);
}

sub xy2ll {
  my ($x,$y)=@_;
  my ($lat,$lon);
  if (exists $cvt{scale}) {
    $x/=$cvt{scale};
    $y/=$cvt{scale};
  }
  if (exists $cvt{crop}) {
    $x+=$cvt{crop}{left};
    $y+=$cvt{crop}{top};
  }
  if ($cvt{plotmode} eq 'chart') {
    my $ay=$y-$cvt{ycen};
    my $ax=$x-$cvt{xcen};
    my $r=sqrt($ax*$ax+$ay*$ay); # cos^2T+sin^2T=1
    my $theta=atan2($ay,$ax);
    $lat=($r-$cvt{rc})/$cvt{rm};
    $lon=($theta-$cvt{thc})/$cvt{thm};
  } elsif ($cvt{plotmode} eq 'plain') {
    $lat=($y-$cvt{yoffset})/$cvt{yscale};
    $lon=($x-$cvt{xoffset})/$cvt{xscale};
  }
  return ($lat,$lon);
}

sub yaml_load_file {
  my $file=shift;
  open (I,'<',$file) || die "Can't load $file\n";
  my $data=join('',<I>);
  close I;
  my $r=Load($data) || die "Can't decode $file\n";
  return $r;
}

sub plot {
  my %d=@_;
  # img, x, y, unit, style, colour, scale
  my $sym=$d{img};
  if ($d{style} eq 'friendly') {
    if ($d{unit}{type} eq 'surface') {
      $sym->arc(x => $d{x},
                y => $d{y},
                r => $d{scale},
                filled => 0,
                color => $d{colour});
    } elsif ($d{unit}{type} =~ /^(airborne|helicopter|missile)$/) {
      $sym->arc(x => $d{x},
                y => $d{y},
                r => $d{scale},
                filled => 0,
                d1 => 180,
                d2 => 0,
                color => $d{colour});
      if ($d{unit}{type} eq 'helicopter') {
        $sym->polyline(color => $d{colour},
                       points => [
                         [$c60*$d{scale}+$d{x},-$s60*$d{scale}+$d{y}],
                         [$c60*$d{scale}*1.4+$d{x},-$s60*$d{scale}*1.4+$d{y}],
                         [$c60*$d{scale}*2+$d{x},-$s60*$d{scale}*1.4+$d{y}],
                           ]
                         );
        $sym->polyline(color => $d{colour},
                       points => [
                         [-$c60*$d{scale}+$d{x},-$s60*$d{scale}+$d{y}],
                         [-$c60*$d{scale}*1.4+$d{x},-$s60*$d{scale}*1.4+$d{y}],
                         [-$c60*$d{scale}*2+$d{x},-$s60*$d{scale}*1.4+$d{y}],
                           ]);
      }
    } elsif ($d{unit}{type} =~ /^(submarine|torpedo)$/) {
      $sym->arc(x => $d{x},
                y => $d{y},
                r => $d{scale},
                filled => 0,
                d1 => 0,
                d2 => 180,
                color => $d{colour});
    } elsif ($d{unit}{type} eq 'mine') {
      $sym->line(color => $d{colour},
                 x1 => -0.7*$d{scale}+$d{x},
                 y1 => $d{y},
                 x2 => -0.9*$d{scale}+$d{x},
                 y2 => $d{y});
      $sym->line(color => $d{colour},
                 x1 => 0.7*$d{scale}+$d{x},
                 y1 => $d{y},
                 x2 => 0.9*$d{scale}+$d{x},
                 y2 => $d{y});
      $sym->line(color => $d{colour},
                 x1 => $d{x},
                 y1 => -0.7*$d{scale}+$d{y},
                 x2 => $d{x},
                 y2 => -0.9*$d{scale}+$d{y});
      $sym->line(color => $d{colour},
                 x1 => $d{x},
                 y1 => 0.7*$d{scale}+$d{y},
                 x2 => $d{x},
                 y2 => 0.9*$d{scale}+$d{y});
    }
  } elsif ($d{style} eq 'neutral') {
    if ($d{unit}{type} eq 'surface') {
      $sym->box(color => $d{colour},
                xmin => $d{x}-$d{scale},
                ymin => $d{y}-$d{scale},
                xmax => $d{x}+$d{scale},
                ymax => $d{y}+$d{scale});
    } elsif ($d{unit}{type} =~ /^(airborne|helicopter|missile)$/) {
      $sym->polyline(color => $d{colour},
                     points => [
                       [$d{x}-$d{scale},$d{y}],
                       [$d{x}-$d{scale},$d{y}-$d{scale}],
                       [$d{x}+$d{scale},$d{y}-$d{scale}],
                       [$d{x}+$d{scale},$d{y}],
                         ]);
      if ($d{unit}{type} eq 'helicopter') {
        $sym->polyline(color => $d{colour},
                       points => [
                         [$d{x}-$d{scale}*0.5,$d{y}-$d{scale}],
                         [$d{x}-$d{scale}*0.5,$d{y}-$d{scale}*1.3],
                         [$d{x}-$d{scale}*0.9,$d{y}-$d{scale}*1.3],
                           ]);
        $sym->polyline(color => $d{colour},
                       points => [
                         [$d{x}+$d{scale}*0.5,$d{y}-$d{scale}],
                         [$d{x}+$d{scale}*0.5,$d{y}-$d{scale}*1.3],
                         [$d{x}+$d{scale}*0.9,$d{y}-$d{scale}*1.3],
                           ]);
      }
    } elsif ($d{unit}{type} =~ /^(submarine|torpedo)$/) {
      $sym->polyline(color => $d{colour},
                     points => [
                       [$d{x}-$d{scale},$d{y}],
                       [$d{x}-$d{scale},$d{y}+$d{scale}],
                       [$d{x}+$d{scale},$d{y}+$d{scale}],
                       [$d{x}+$d{scale},$d{y}],
                         ]);
    } elsif ($d{unit}{type} =~ /^(sonobuoy|mine)$/) {
      $sym->box(color => $d{colour},
                xmin => $d{x}-$d{scale}*0.7,
                ymin => $d{y}-$d{scale}*0.7,
                xmax => $d{x}+$d{scale}*0.7,
                ymax => $d{y}+$d{scale}*0.7);
      if ($d{unit}{type} eq 'mine') {
        $sym->line(color => $d{colour},
                   x1 => -0.7*$d{scale}+$d{x},
                   y1 => $d{y},
                   x2 => -0.9*$d{scale}+$d{x},
                   y2 => $d{y});
        $sym->line(color => $d{colour},
                   x1 => 0.7*$d{scale}+$d{x},
                   y1 => $d{y},
                   x2 => 0.9*$d{scale}+$d{x},
                   y2 => $d{y});
        $sym->line(color => $d{colour},
                   x1 => $d{x},
                   y1 => -0.7*$d{scale}+$d{y},
                   x2 => $d{x},
                   y2 => -0.9*$d{scale}+$d{y});
        $sym->line(color => $d{colour},
                   x1 => $d{x},
                   y1 => 0.7*$d{scale}+$d{y},
                   x2 => $d{x},
                   y2 => 0.9*$d{scale}+$d{y});
      }
    }
  } elsif ($d{style} eq 'hostile') {
    if ($d{unit}{type} eq 'surface') {
      $sym->polyline(color => $d{colour},
                     points => [
                       [$d{x},$d{y}-$d{scale}],
                       [$d{x}+$d{scale},$d{y}],
                       [$d{x},$d{y}+$d{scale}],
                       [$d{x}-$d{scale},$d{y}],
                       [$d{x},$d{y}-$d{scale}],
                         ]);
    } elsif ($d{unit}{type} =~ /^(airborne|helicopter|missile)$/) {
      $sym->polyline(color => $d{colour},
                     points => [
                       [$d{x}-$d{scale},$d{y}],
                       [$d{x},$d{y}-$d{scale}],
                       [$d{x}+$d{scale},$d{y}],
                         ]);
      if ($d{unit}{type} eq 'helicopter') {
        $sym->polyline(color => $d{colour},
                       points => [
                         [$d{x}-$d{scale}*0.3,$d{y}-$d{scale}*0.7],
                         [$d{x}-$d{scale}*0.6,$d{y}-$d{scale}],
                         [$d{x}-$d{scale},$d{y}-$d{scale}],
                           ]);
        $sym->polyline(color => $d{colour},
                       points => [
                         [$d{x}+$d{scale}*0.3,$d{y}-$d{scale}*0.7],
                         [$d{x}+$d{scale}*0.6,$d{y}-$d{scale}],
                         [$d{x}+$d{scale},$d{y}-$d{scale}],
                           ]);
      }
    } elsif ($d{unit}{type} =~ /^(submarine|torpedo)$/) {
      $sym->polyline(color => $d{colour},
                     points => [
                       [$d{x}-$d{scale},$d{y}],
                       [$d{x},$d{y}+$d{scale}],
                       [$d{x}+$d{scale},$d{y}],
                         ]);
    } elsif ($d{unit}{type} =~ /^(sonobuoy|mine)$/) {
      $sym->polyline(color => $d{colour},
                     points => [
                       [$d{x},$d{y}-$d{scale}*0.7],
                       [$d{x}+$d{scale}*0.7,$d{y}],
                       [$d{x},$d{y}+$d{scale}*0.7],
                       [$d{x}-$d{scale}*0.7,$d{y}],
                       [$d{x},$d{y}-$d{scale}*0.7],
                         ]);
      if ($d{unit}{type} eq 'mine') {
        $sym->line(color => $d{colour},
                   x1 => -0.7*$d{scale}+$d{x},
                   y1 => $d{y},
                   x2 => -0.9*$d{scale}+$d{x},
                   y2 => $d{y});
        $sym->line(color => $d{colour},
                   x1 => 0.7*$d{scale}+$d{x},
                   y1 => $d{y},
                   x2 => 0.9*$d{scale}+$d{x},
                   y2 => $d{y});
        $sym->line(color => $d{colour},
                   x1 => $d{x},
                   y1 => -0.7*$d{scale}+$d{y},
                   x2 => $d{x},
                   y2 => -0.9*$d{scale}+$d{y});
        $sym->line(color => $d{colour},
                   x1 => $d{x},
                   y1 => 0.7*$d{scale}+$d{y},
                   x2 => $d{x},
                   y2 => 0.9*$d{scale}+$d{y});
      }
    }
  }
  if ($d{unit}{type} eq 'sonobuoy') {
    $sym->line(color => $d{colour},
               x1 => $d{x},
               y1 => $d{y}-$d{scale}*0.7,
               x2 => $d{x},
               y2 => $d{y}-$d{scale}*2);
    foreach my $y (-1.4,-2.0) {
      $sym->line(color => $d{colour},
                 x1 => $d{x},
                 y1 => $d{y}+$y*$d{scale},
                 x2 => $d{x}-$d{scale}*0.7,
                 y2 => $d{y}+$y*$d{scale}
                   );
    }
  }
  my $rad=0.2;
  if ($d{unit}{type} eq 'torpedo') {
    $rad=0;
    $sym->line(color => $d{colour},
               x1 => $d{x}-$d{scale}*0.2,
               y1 => $d{y},
               x2 => $d{x}+$d{scale}*0.2,
               y2 => $d{y}
                 );
    $sym->line(color => $d{colour},
               x1 => $d{x},
               y1 => $d{y},
               x2 => $d{x},
               y2 => $d{y}+$d{scale}*0.5
                 );
  } elsif ($d{unit}{type} eq 'missile') {
    $rad=0;
    $sym->polyline(color => $d{colour},
                   points => [
                     [$d{x}-$d{scale}*0.2,$d{y}],
                     [$d{x}-$d{scale}*0.2,$d{y}-$d{scale}*0.5],
                     [$d{x},$d{y}],
                     [$d{x}+$d{scale}*0.2,$d{y}-$d{scale}*0.5],
                     [$d{x}+$d{scale}*0.2,$d{y}],
                       ]);
  } elsif ($d{unit}{type} =~ /^(sonobuoy|mine)$/) {
    if ($d{style} eq 'friendly') {
      $rad=0.7;
    } else {
      $rad=0;
    }
  }
  if ($rad) {
    $sym->arc(x => $d{x},
              y => $d{y},
              r => $d{scale}*$rad,
              filled => 0,
              color => $d{colour});
  }
  if (exists $d{unit}{course}) {
    $sym->line(color => $d{colour},
               x1 => $d{x}+$d{scale}*0.5*sin(deg2rad($d{unit}{course})),
               y1 => $d{y}-$d{scale}*0.5*cos(deg2rad($d{unit}{course})),
               x2 => $d{x}+$d{scale}*2*sin(deg2rad($d{unit}{course})),
               y2 => $d{y}-$d{scale}*2*cos(deg2rad($d{unit}{course})),
                 );
  }
  my @text=($d{unit}->{label} || $d{unit}->{short} || substr(uc($d{unit}{name}),0,3)) || 'XXX';
  if (0 && exists $d{unit}->{course}) {
    push @text,sprintf('%03d',$d{unit}->{course});
    if ($d{unit}->{speed}<1000) {
      push @text,sprintf('%03d',$d{unit}->{speed});
    } else {
      push @text,$d{unit}->{speed};
    }
    if (exists $d{unit}->{altitude} && $d{unit}->{altitude}>0) {
      push @text,sprintf('%03d',int($d{unit}->{altitude}/304.8+.5));
    }
  }
  my $ty=-0.5;
  foreach (@text) {
    $d{img}->string(x => $d{x}+$d{scale}*1.2,
                    y => $d{y}+$ty*$d{scale},
                    font => $fn,
                    color => $d{colour},
                    string => $_);
    $ty++;
  }
}

sub locparse {
  my $h=shift @_;
  my $backup=(shift @_) || undef;
  if (exists $h->{lat} && exists $h->{lon}) {
    return ($h->{lat},$h->{lon});
  } elsif (exists $h->{loc}) {
    if ($h->{loc} =~ /me/) {
      my @ll=locparse($backup);
      $h->{loc} =~ s/me/$ll[0],$ll[1]/g;
    }
    if ($h->{loc} =~ /^\s*([-.0-9]+),\s*([-.0-9]+)\s*\+\s*([-.0-9]+)\s*\@\s*([-.0-9]+)\s*$/) {
      return $geo->at($1,$2,$3*$nm,$4);
    } elsif ($h->{loc} =~ /^\s*([-.0-9]+),\s*([-.0-9]+)\s*$/) {
      return ($1,$2);
    } else {
      die "Bad loc\n".Dump($h);
    }
  } else {
    die "Bad input\n".Dump($h);
  }
}

sub gendraw {
  my ($img,$ovl,$o)=@_;
  my @trace;
  my @label;
  my $close=0;
  if ($o->{type} eq 'arc') {
    my $loc=join(',',locparse($o));
    $o->{type}='path';
    if (exists $o->{minradius}) {
      $o->{segments}=[{cmd => 'move',
                       loc => "$loc+$o->{minradius}\@$o->{anglestart}"},
                      {cmd => 'line',
                       loc => "$loc+$o->{radius}\@$o->{anglestart}"},
                      {cmd => 'arc',
                       loc => $loc,
                       radius => $o->{radius},
                       angle => $o->{angleend}},
                      {cmd => 'line',
                       loc => "$loc+$o->{minradius}\@$o->{angleend}"},
                      {cmd => 'arc',
                       loc => $loc,
                       radius => $o->{minradius},
                       angle => $o->{anglestart}},
                      {cmd => 'close'}];
    } else {
      $o->{segments}=[{cmd => 'move',
                       loc => $loc},
                      {cmd => 'line',
                       loc => "$loc+$o->{radius}\@$o->{anglestart}"},
                      {cmd => 'arc',
                       loc => $loc,
                       radius => $o->{radius},
                       angle => $o->{angleend}},
                      {cmd => 'line',
                       loc => $loc},
                      {cmd => 'close'}];
    }
  }
  if ($o->{type} eq 'circle') {
    foreach my $angle (0..360) {
      push @trace,[$geo->at(locparse($o),$o->{radius}*$nm,$angle)];
    }
    $close=1;
    @label=@{$trace[45]};
  } elsif ($o->{type} eq 'icon') {
    my $icon=Imager->new(file => $o->{file});
    if (defined $icon) {
      my @offset=map {$_/-2} ($icon->getwidth,$icon->getheight);
      $img->rubthrough(src => $icon,
                       tx => $offset[0],
                       ty => $offset[1]
                         );
    }
  } elsif ($o->{type} eq 'path') {
    foreach my $pt (@{$o->{segments}}) {
      if ($pt->{cmd} eq 'move' && (scalar @trace) == 0) {
        @trace=([locparse($pt,$o)]);
      } elsif ($pt->{cmd} eq 'line') {
        push @trace,[locparse($pt,$o)];
        if (scalar @trace > 1) {
          my @l;
          @l=splice @trace,-2;
          push @trace,interpolate_latlon(@l);
        }
      } elsif ($pt->{cmd} eq 'arc') {
        my @c=locparse($pt,$o);
        my ($r,$a)=$geo->to(@c,@{$trace[-1]});
        my $step=1;
        if ($a-$pt->{angle}>180) {
          $a-=360;
        }
        if ($pt->{angle}-$a>180) {
          $pt->{angle}-=360;
        }
        if ($a>$pt->{angle}) {
          $step=-1;
        }
        my $m=$pt->{angle}-$a;
        for (my $ai=0;$ai<=1;$ai+=.01) {
          push @trace,[$geo->at(@c,$r,$a+$m*$ai)];
        }
      } elsif ($pt->{cmd} eq 'close') {
        $close=1;
      }
    }
    if ($close) {
      push @trace,$trace[0];
    }
    @label=@{$trace[0]};
  } elsif ($o->{type} eq 'box') {
    foreach my $pi ([qw(n w)],[qw(n e)],[qw(s e)],[qw(s w)],[qw(n w)]) {
      push @trace,[$o->{$pi->[0]},$o->{$pi->[1]}];
    }
    @label=@{$trace[1]};
    @trace=interpolate_latlon(@trace);
    $close=1;
  }
  my @points=map {[ll2xy(@{$_})]} @trace;
  if ($close) {
    my @oc=Imager::Color->new($o->{colour})->rgba;
    $oc[3]=128;
    if (exists $o->{alpha}) {
      $oc[3]=$o->{alpha};
    }
    $ovl->polygon(points => \@points,
                  color => Imager::Color->new(@oc));
  }
  if (!exists $o->{border} || $o->{border} ne 'null') {
    $img->polyline(points => \@points,
                   color => ($o->{border} || $o->{colour}));
  }
  if (exists $o->{label}) {
    my @lxy=ll2xy(@label);
    $img->string(x => $lxy[0],
                 y => $lxy[1],
                 font => $fn,
                 color => $o->{colour},
                 string => $o->{label});
  }
}

sub interpolate_greatcircle {
  my @plist=@_;
  my @out=$plist[0];
  my $resolution=1000; # metres
  foreach my $index (1..$#plist) {
    my ($r,$a)=$geo->to(@{$plist[$index-1]},@{$plist[$index]});
    if ($r>$resolution) {
      for (my $rr=$resolution;$rr<$r;$rr+=$resolution) {
        push @out,[$geo->at(@{$plist[$index-1]},$rr,$a)];
      }
    }
    push @out,$plist[$index];
  }
  return @out;
}

sub interpolate_latlon {
  my @plist=@_;
  my @out=$plist[0];
  my $resolution=1000; # metres
  foreach my $index (1..$#plist) {
    my $r=$geo->range(@{$plist[$index-1]},@{$plist[$index]});
    if ($r>$resolution) {
      my @m=map {$plist[$index][$_]-$plist[$index-1][$_]} (0,1);
      my @c=map {$plist[$index-1][$_]} (0,1);
      my $step=$resolution/$r;
      for (my $rr=$step;$rr<1;$rr+=$step) {
        push @out,[$m[0]*$rr+$c[0],$m[1]*$rr+$c[1]];
      }
    }
    push @out,$plist[$index];
  }
  return @out;
}

sub timeformat {
  my $t=shift;
  my $o=strftime('%H%M%S',localtime($t));
  $o =~ s/00$//;
  return $o;
}

sub getdepth {
  my ($mlat,$mlon)=@_;
  use bigint;
  my $offset=4*(($mlon+10800)+(5400-$mlat)*21601);
  seek DEPTH,$offset,0;
  my $r;
  read DEPTH,$r,4;
  return unpack('f',$r);
}

sub mapband {
  my $d=shift;
  my $band;
  if ($d>=-9.144) {             # no submarines at all
    $band='S1';
  } elsif ($d>=-36.576) {       # submarines only on surface
    $band='S2';
  } elsif ($d>=-50) {           # normal shallow
    $band='S3';
  } elsif ($d>=-500) {
    $band='I'.(1+int((-1-$d)/100));
  } elsif ($d>=-1200) {
    $band='D'.(int((-1-$d)/150)-2);
  } else {
    $band='VD';
  }
  return $band;
}

sub shadeband {
  my $d=shift;
  my $band;
  if ($d>=-9.144) {             # no submarines at all
    $band='x';
  } elsif ($d>=-50) {           # normal shallow
    $band='S';
  } elsif ($d>=-500) {
    $band='I';
  } elsif ($d>=-1200) {
    $band='D';
  } else {
    $band='V';
  }
  return $band;
}

sub unitband {
  my $d=shift;
  my $band;
  if ($d>13500) {
    $band='VH';
  } elsif ($d>7500) {
    $band='H';
  } elsif ($d>2000) {
    $band='M';
  } elsif ($d>100) {
    $band='L';
  } elsif ($d>30) {
    $band='NoE';
  } elsif ($d>0) {
    $band='VL';
  } elsif ($d>=-25) {
    $band='P';
  } elsif ($d>=-50) {
    $band='S';
  } elsif ($d>=-500) {
    $band='I'.(1+int((-1-$d)/100));
  } elsif ($d>=-1200) {
    $band='D'.(int((-1-$d)/150)-2);
  } else {
    $band='VD';
  }
  return $band;
}

# this code from CTAN, apparently!
# http://www.tex.ac.uk/CTAN/graphics/mathspic/perl/sourcecode113.html

sub triangleArea {
  my ($xA, $yA, $xB, $yB, $xC, $yC)=@_;
  my ($lenAB, $lenBC, $lenCA, $s);

  $lenAB = Length($xA,$yA,$xB,$yB);
  $lenBC = Length($xB,$yB,$xC,$yC);
  $lenCA = Length($xC,$yC,$xA,$yA);
  $s = ($lenAB + $lenBC + $lenCA) / 2;
  return sqrt($s * ($s - $lenAB)*($s - $lenBC)*($s - $lenCA));
}

sub circumCircleCenter {
  my ($xA, $yA, $xB, $yB, $xC, $yC, $lc)=@_;
  my ($deltay12, $deltax12, $xs12, $ys12);
  my ($deltay23, $deltax23, $xs23, $ys23);
  my ($xcc, $ycc);
  my ($m23, $mr23, $c23, $m12, $mr12, $c12);
  my ($sideA, $sideB, $sideC, $a, $radius);

  if (abs(triangleArea($xA, $yA, $xB, $yB, $xC, $yC)) < 0.0000001) {
    PrintErrorMessage("Area of triangle is zero!",$lc);
    return (0,0,0);
  }
  $deltay12 = $yB - $yA;
  $deltax12 = $xB - $xA;
  $xs12 = $xA + $deltax12 / 2;
  $ys12 = $yA + $deltay12 / 2;
  #
  $deltay23 = $yC - $yB;
  $deltax23 = $xC - $xB;
  $xs23 = $xB + $deltax23 / 2;
  $ys23 = $yB + $deltay23 / 2;
  #
 CCXYLINE:{
    if (abs($deltay12) < 0.0000001) {
      $xcc = $xs12;
      if (abs($deltax23) < 0.0000001) {
        $ycc = $ys23;
        last CCXYLINE;
      } else {
        $m23 = $deltay23 / $deltax23;
        $mr23 = -1 / $m23;
        $c23 = $ys23 - $mr23 * $xs23;
        $ycc = $mr23 * $xs12 + $c23;
        last CCXYLINE;
      }
    }
    if (abs($deltax12) < 0.0000001) {
      $ycc = $ys12;
      if (abs($deltay23) < 0.0000001) {
        $xcc = $xs23;
        last CCXYLINE;
      } else {
        $m23 = $deltay23 / $deltax23;
        $mr23 = -1 / $m23;
        $c23 = $ys23 - $mr23 * $xs23;
        $xcc = ($ys12 - $c23) / $mr23;
        last CCXYLINE;
      }
    }
    if (abs($deltay23) < 0.0000001) {
      $xcc = $xs23;
      if (abs($deltax12) < 0.0000001) {
        $ycc = $ys12;
        last CCXYLINE;
      } else {
        $m12 = $deltay12 / $deltax12;
        $mr12 = -1 / $m12;
        $c12 = $ys12 - $mr12 * $xs12;
        $ycc = $mr12 * $xcc + $c12;
        last CCXYLINE;
      }
    }
    if (abs($deltax23) < 0.0000001) {
      $ycc = $ys23;
      if (abs($deltay12) < 0.0000001) {
        $xcc = $xs12;
        last CCXYLINE;
      } else {
        $m12 = $deltay12 / $deltax12;
        $mr12 = -1 / $m12;
        $c12 = $ys12 - $mr12 * $xs12;
        $xcc = ($ycc - $c12) / $mr12;
        last CCXYLINE;
      }
    }
    $m12 = $deltay12 / $deltax12;
    $mr12 = -1 / $m12;
    $c12 = $ys12 - $mr12 * $xs12;
    #-----
    $m23 = $deltay23 / $deltax23;
    $mr23 = -1 / $m23;
    $c23 = $ys23 - $mr23 * $xs23;
    $xcc = ($c23 - $c12) / ($mr12 - $mr23);
    $ycc = ($c23 * $mr12 - $c12 * $mr23) / ($mr12 - $mr23);
  }
  #
  $sideA = &Length($xA,$yA,$xB,$yB);
  $sideB = &Length($xB,$yB,$xC,$yC);
  $sideC = &Length($xC,$yC,$xA,$yA);
  $a = triangleArea($xA, $yA, $xB, $yB, $xC, $yC);
  $radius = ($sideA * $sideB * $sideC) / (4 * $a);
  #
  return ($xcc, $ycc, $radius);
}

sub Length {
  my ($xA, $yA, $xB, $yB)=@_;
  return sqrt(($xB - $xA)**2 + ($yB - $yA)**2);
}

__DATA__
<html>
<head>
<meta charset="utf-8">
<title><tmpl_var name=stub escape=html> <tmpl_var name=side escape=html></title></head>
<body>
<center><tmpl_if name=full><a href="<tmpl_var name=stub escape=html>.<tmpl_var name=keyword escape=html>.full.jpg"></tmpl_if><img src="<tmpl_var name=stub escape=html>.<tmpl_var name=keyword escape=html>.jpg"><tmpl_if name=full></a></tmpl_if></center>
<table border=1>
<tr><td colspan=3 rowspan=3></td><td><i>name</i></td><tmpl_loop name=enemyunit><td colspan=2><tmpl_var name=id></td></tmpl_loop></tr>
<tr><td><i>speed</i></td><tmpl_loop name=enemyunit><td colspan=2><tmpl_var name=speed></td></tmpl_loop></tr>
<tr><td><i>course</i></td><tmpl_loop name=enemyunit><td colspan=2><tmpl_var name=course>&deg;</td></tmpl_loop></tr>
<tr><td><i>name</i></td><td><i>speed</i></td><td><i>course</i></td><td><i>alt/depth</i></td><tmpl_loop name=enemyunit><td colspan=2><tmpl_if name=height><tmpl_var name=height></tmpl_if></td></tmpl_loop></tr>
<tmpl_loop name=rangetable>
<tr><td><tmpl_var name=id>: <tmpl_var name=name></td>
<td><tmpl_var name=speed></td>
<td><tmpl_var name=course>&deg;</td>
<td><tmpl_if name=height><tmpl_var name=height></tmpl_if></td>
<tmpl_loop name=enemyunit>
<td><tmpl_var name=range></td>
<td><tmpl_if name=relative><tmpl_var name=bearing>&deg; <font color=<tmpl_var name=relcol>>[<tmpl_var name=relative>]</font></tmpl_if></td>
</tmpl_loop>
</tr>
</tmpl_loop>
</table>
</body>
</html>
