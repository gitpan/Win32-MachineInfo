package Win32::MachineInfo;

use 5.006;
use strict;
use warnings;

our @EXPORT_OK = qw(GetMachineInfo);
our $VERSION = '0.05';

use Win32::TieRegistry qw(:KEY_ :REG_);
use POSIX qw(ceil strftime);

sub reformat_date
{
    my $date = shift;
    return "" unless $date && $date =~ qr(^\d+/\d+/\d+$);

    # American date format assumed
    my ($month, $day, $year) = split "/", $date;
    if ($year > 50) {
        $year = "19$year";
    } else {
        $year = "20$year";
    }

    return sprintf "%04d-%02d-%02d", $year, $month, $day;
}

sub GetMachineInfo
{
    my $host = shift || "";
    my $info = shift; # should be a ref to a hash!

    if (ref $info ne "HASH") {
        die "Usage: GetMachineInfo(\$host, \\%info)";
    }
    %{$info} = ();

    my $hklm = $Registry->Connect($host, "HKEY_LOCAL_MACHINE",
        {Access=>KEY_READ})
        or return 0;

    $hklm->SplitMultis(1);

    # OS Information
    my $osinfo = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion"};
    $info->{"osversion"} = $osinfo->{"CurrentVersion"} || "";
    $info->{"service_pack"} = $osinfo->{"CSDVersion"} || "";
    $info->{"registered_organization"} =
        $osinfo->{"RegisteredOrganization"} || "";
    $info->{"registered_owner"} = $osinfo->{"RegisteredOwner"} || "";
    $info->{"system_root"} = $osinfo->{"SystemRoot"} || "";
    if (my $install_date = hex($osinfo->{"InstallDate"})) {
        $info->{"install_date"} = strftime("%Y-%m-%d", localtime $install_date);
        $info->{"install_time"} = strftime("%H:%M", localtime $install_date);
    } else {
        $info->{"install_date"} = $info->{"install_time"} = "";
    }
    
    if (my $product_type = $hklm->{"SYSTEM\\CurrentControlSet\\Control\\ProductOptions\\ProductType"}) {
        $info->{"product_type"} =  $product_type;
    }

    # IE Version
    my $ieinfo = $hklm->{"SOFTWARE\\Microsoft\\Internet Explorer"};
    $info->{"ieversion"} = $ieinfo->{"Version"} || "";

    # Computer Name
    my $computer_name = $hklm->{"SYSTEM\\CurrentControlSet\\Control\\ComputerName\\ComputerName\\ComputerName"};
    $info->{"computer_name"} = $computer_name || "";

    # BIOS Information
    my $systeminfo = $hklm->{"HARDWARE\\DESCRIPTION\\System"};
    $info->{"system_bios_date"} = reformat_date($systeminfo->{"SystemBiosDate"});
    if (my ($system_bios, $type) = $systeminfo->GetValue("SystemBiosVersion")) {
        # Catch Itanium systems running Windows 2003 which have a REG_SZ for
        # the SystemBiosVersion value instead of a REG_MULTI_SZ.
        if ($type == REG_SZ) {
            $info->{"system_bios_version"} = $system_bios;
        } else { # REG_MULTI_SZ 
            $info->{"system_bios_version"} = ${$system_bios}[0];
        }
    } else {
        $info->{"system_bios_version"} = "";
    }
    $info->{"video_bios_date"} = reformat_date($systeminfo->{"VideoBiosDate"});
    if (my $video_bios = $systeminfo->{"VideoBiosVersion"}) {
        $info->{"video_bios_version"} = ${$video_bios}[0];
    } else {
        $info->{"video_bios_version"} = "";
    }

    # Processor Information
    $info->{"number_of_processors"} = $hklm->{"SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment\\NUMBER_OF_PROCESSORS"} || "";
    my $cpuinfo = $hklm->{"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"};
    # note that processor speed can vary (slightly) from boot to boot
    if (my $mhz = hex($cpuinfo->{"~MHZ"})) {
        $info->{"processor_speed"} = "$mhz MHz";
    } else {
        $info->{"processor_speed"} = "";
    }
    $info->{"processor_vendor"} = $cpuinfo->{"VendorIdentifier"} || "";
    $info->{"processor_identifier"} = $cpuinfo->{"Identifier"} || "";
    my $processor_name = cpuid($info->{'processor_vendor'},
                               $info->{'processor_identifier'});
    $info->{"processor_name"} = $processor_name || "";

    # Memory Information
    my $memoryinfo =
        $hklm->{"HARDWARE\\RESOURCEMAP\\System Resources\\Physical Memory"};
    $info->{"memory"} = ceil((unpack "L*", $memoryinfo->{".Translated"})[-1]
        / 1024 / 1024 + 16) . " MB";

    # Video Information
    # We look in HKLM\HARDWARE\DEVICEMAP\VIDEO0 to find a pointer
    # to the location of the video settings.
    my $videoinfo = $hklm->{"HARDWARE\\DEVICEMAP\\VIDEO"};
    # According to Q200435, Windows will load \Device\Video0
    my $videokeyname = $videoinfo->GetValue("\\Device\\Video0");
    # On Windows NT/2000 it will refer to a Services entry,
    # and its name will be a comprehensible string, e.g. voodoo7
    # REGISTRY\Machine\System\ControlSet001\Services\<display driver>\Device0
    # On Windows XP it will refer to a Control entry,
    # and its name will be a GUID
    # \Registry\Machine\System\CurrentControlSet\Control\Video\<display driver GUID\0000
    $videokeyname =~ s/.*\\Machine\\//;
    $videokeyname =~ s/ControlSet\d\d\d/CurrentControlSet/;
    my $videokey = $hklm->{$videokeyname};
    if (my $videoadapter = $videokey->{"HardwareInformation.AdapterString"}) {
        $videoadapter =~ s/\x00//g; # unicode -> ascii
        $info->{"video_adapter"} = $videoadapter;
    } else {
        $info->{"video_adapter"} = "";
    }

    # Display Settings
    # On Windows NT/2000 the display settings are stored in
    # HKLM\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\SERVICES\<display driver>\VIDEO0
    # On Windows XP the display settings are stored in
    # HKLM\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Control\VIDEO\<display driver GUID>\0000
    if (my $videoconfig = $hklm->{"SYSTEM\\CurrentControlSet\\Hardware Profiles\\Current\\$videokeyname"}) {
        my $xres = hex($videoconfig->{"DefaultSettings.XResolution"} || "");
        my $yres = hex($videoconfig->{"DefaultSettings.YResolution"} || "");
        my $bits = hex($videoconfig->{"DefaultSettings.BitsPerPel"} || "");
        if ($xres) {
            $info->{"display_resolution"} = $xres . "x" . $yres . "x". $bits;
        } else {
            $info->{"display_resolution"} = "";
        }
        if (my $vref = hex($videoconfig->{"DefaultSettings.VRefresh"} || "")) {
            $info->{"refresh_rate"} = "$vref Hz";
        } else {
            $info->{"refresh_rate"} = "";
        }
    }

    # Hotfixes (initial support)
    if (my $hotfixes = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Hotfix"}) {
        my @hotfixes = $hotfixes->SubKeyNames;
        $info->{"hotfixes"} = \@hotfixes;
    }

    # Finished
    return 1;
}

sub cpuid
{
    my $vendor = shift;
    my $identifier = shift;

    our %table = (
        "AuthenticAMD" => {
            "4" => {
                "3" => "486DX2",
                "7" => "486DX2-WB",
                "8" => "486DX4",
                "9" => "486DX4-WB",
                "14" => "Am5x86-WT",
                "15" => "Am5x86-WB",
            },
            "5" => {
                "0" => "K5/SSA5",
                "1" => "K5",
                "2" => "K5",
                "3" => "K5",
                "6" => "K6 model 6",
                "7" => "K6 model 7",
                "8" => "K6-2 model 8",
                "9" => "K6-3",
            },
            "6" => {
                "1" => "Athlon",
                "2" => "Athlon",
                "3" => "Duron",
                "4" => "Athlon",
            },
        },
        "GenuineIntel" => {
            "4" => {
                "0" => "486DX",
                "1" => "486DX",
                "2" => "486SX",
                "3" => "486DX2",
                "4" => "486SL",
                "5" => "486SX2",
                "7" => "486DX2 WB",
                "8" => "486DX4",
                "9" => "486DX4 WB",
            },
            "5" => {
                "0" => "Pentium 60/66 A-step",
                "1" => "Pentium P5",
                "2" => "Pentium P54C",
                "3" => "Pentium Overdrive",
                "4" => "Pentium MMX P55C",
                "7" => "Mobile Pentium P54C",
                "8" => "Mobile Pentium MMX P55C",
            },
            "6" => {
                "1" => "Pentium Pro",
                "3" => "Pentium II",
                "5" => "Pentium II/Celeron",
                "6" => "Pentium II/Celeron",
                "7" => "Pentium III",
                "8" => "Pentium III",
            },
        }
    );

    our %family_table = (
        "AuthenticAMD" => {
            "4" => "486",
            "5" => "K5/K6",
            "6" => "Athlon",
        },
        "GenuineIntel" => {
            "3" => "386",
            "4" => "486",
            "5" => "Pentium",
            "6" => "P6", # Pentium Pro, Pentium II, Pentium III
            "7" => "Itanium",
            "15" => "Pentium IV",
        },
        "CyrixInstead" => {
            "4" => "Cx5x86",
            "5" => "Cx6x86",
            "6" => "6x86MX",
        },
    );

    our %vendor_table = (
        "AuthenticAMD" => "AMD",
        "GenuineIntel" => "Intel",
        "CyrixInstead" => "Cyrix",
    );

    if (my ($arch, $family, $model) =
        ($identifier =~ /^(x86|ia64) Family (\d+) Model (\d+)/)) {

        my $vendor_name = $vendor_table{$vendor};

        my $processor_name = $table{$vendor}{$family}{$model};
        if ($processor_name) {
            return "$vendor_name $processor_name Processor";
        }

        my $family_name = $family_table{$vendor}{$family};
        if ($family_name) {
            return "$vendor_name $family_name Processor Family";
        }

    }
    return "Unrecognised Processor";
}

1;

__END__

=head1 NAME

Win32::MachineInfo - Basic Windows NT/2000/XP OS and Hardware Info

=head1 SYNOPSIS

    use Win32::MachineInfo;

    my $host = shift || "";
    if (Win32::MachineInfo::GetMachineInfo($host, \%info)) {
        for $key (sort keys %info) {
            print "$key=", $info{$key}, "\n";
        }
    } else {
        print "Error: $^E\n";
    }

=head1 DESCRIPTION

Win32::MachineInfo is a module that retrieves basic OS, CPU, Memory,
and Video information from a remote Windows NT/2000/XP machine. It uses
Win32::TieRegistry to retrieve the information, which it returns as a hash
structure.

=head1 FUNCTIONS

=over 4

=item Win32::MachineInfo::GetMachineInfo($host, \%info);

where $host is the target machine and %info the hash that will contain the
collected information if the function executes successfully. $host can be
"HOST1", "\\\\HOST1", or "192.168.0.1". The function will return true if it
completes successfully, false otherwise. If the function fails, it will
probably be because it cannot connect to the remote machine's registry; the
error will available through Win32::GetLastError.

=back

The following fields are returned in %info:

=over 4

=item $info{'computer_name'}

=item $info{'processor_vendor'}

=item $info{'processor_name'}

=item $info{'processor_speed'}

=item $info{'memory'}

=item $info{'system_bios_date'}

=item $info{'system_bios_version'}

=item $info{'video_bios_date'}

=item $info{'video_bios_version'}

=item $info{'video_adapter'}

=item $info{'display_resolution'}

=item $info{'refresh_rate'}

=item $info{'osversion'}

=item $info{'service_pack'}

=item $info{'system_root'}

=item $info{'install_date'}

=item $info{'install_time'}

=item $info{'registered_owner'}

=item $info{'registered_organization'}

=back

=head1 EXAMPLES

=head2 Collecting OS Information from a Number of Machines

    use Win32::MachineInfo;

    @fields = qw/computer_name osversion display_resolution/;
    print join(",", @fields), "\n";
    while (<DATA>) {
        chomp;
        Win32::MachineInfo::GetMachineInfo($_, \%info);
        print join ",", @info{@fields};
        print "\n";
    }

    __DATA__
    HOST1
    HOST2
    HOST3

=head1 AUTHOR

James Macfarlane, E<lt>jmacfarla@cpan.orgE<gt>

=head1 SEE ALSO

Win32::TieRegistry

Paul Popour's SRVCPUMEM.PL script was an inspiration and I am indebted to
him for the formula that calculates memory from the value of the ".Translated"
key.

I found the following sites helpful in compiling the 
translation tables that determine the 'processor_name' field
from the processor_vendor and processor_identifier fields:

=over 4

=item *

www.paradicesoftware.com/specs/cpuid/cpuid.htm

=item *

grafi.ii.pw.edu.pl/gbm/x86/cpuid.html

=item *

www.microflextech.com/support/intel/intel.htm

=back

=cut
