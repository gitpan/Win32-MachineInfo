package Win32::MachineInfo;

use 5.006;
use strict;
use warnings;

our @EXPORT_OK = qw(GetMachineInfo);
our $VERSION = '0.02';

use Win32::TieRegistry qw(:KEY_);
use POSIX qw(ceil strftime);

sub reformat_date
{
    my $date = shift;

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

    my $machkey = $Registry->Connect($host, "HKEY_LOCAL_MACHINE",
        {Access=>KEY_READ})
        or return 0;

    $machkey->SplitMultis(1);

    my $key;

    # OS Information
    my $cv = $machkey->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion"};
    my $osversion = $cv->{"CurrentVersion"};
    $info->{"osversion"} = $cv->{"CurrentVersion"};
    $info->{"service_pack"} = $cv->{"CSDVersion"};
    $info->{"registered_organization"} = $cv->{"RegisteredOrganization"};
    $info->{"registered_owner"} = $cv->{"RegisteredOwner"};
    $info->{"system_root"} = $cv->{"SystemRoot"};
    my $install_date = hex($cv->{"InstallDate"});
    $info->{"install_date"} = strftime("%Y-%m-%d", localtime $install_date);
    $info->{"install_time"} = strftime("%H:%M", localtime $install_date);
    
    $info->{"product_type"} = $machkey->{"SYSTEM\\CurrentControlSet\\Control\\ProductOptions\\ProductType"}; # 2000 only

    # IE Version
    $key = $machkey->{"SOFTWARE\\Microsoft\\Internet Explorer"};
    $info->{"ieversion"} = $key->{"Version"};

    # Computer Name
    $key = $machkey->{"SYSTEM\\CurrentControlSet\\Control\\ComputerName\\ComputerName"};
    $info->{"computer_name"} = $key->{"ComputerName"};

    # BIOS Information
    my @versions;
    $key = $machkey->{"HARDWARE\\DESCRIPTION\\System"};
    $info->{"system_bios_date"} = reformat_date($key->{"SystemBiosDate"});
    if (my $system_bios = $key->{"SystemBiosVersion"}) {
        $info->{"system_bios_version"} = ${$system_bios}[0];
    }
    $info->{"video_bios_date"} = reformat_date($key->{"VideoBiosDate"});
    if (my $video_bios = $key->{"VideoBiosVersion"}) {
        $info->{"video_bios_version"} = ${$video_bios}[0];
    }

    # Processor Information
    $key = $machkey->{"SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment"};
    $info->{"number_of_processors"} = $key->{"NUMBER_OF_PROCESSORS"};
    $key = $machkey->{"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"};
    # note the processor speed can vary (slightly) from boot to boot
    $info->{"processor_speed"} = hex($key->{"~MHZ"}) . " MHz";
    #$info->{"processor_name"} = $key->{"ProcessorNameString"}; # 2000 only?
    $info->{"processor_vendor"} = $key->{"VendorIdentifier"};
    $info->{"processor_identifier"} = $key->{"Identifier"};
    my $processor_name = cpuid($info->{'processor_vendor'},
                               $info->{'processor_identifier'});
    $info->{"processor_name"} = $processor_name;

    # Memory Information
    my $memory = $machkey->{"HARDWARE\\RESOURCEMAP\\System Resources\\Physical Memory"};
    $info->{"memory"} = ceil((unpack "L*", $memory->{".Translated"})[-1] / 1024 /1024 + 16) . " MB";

    # Video Information
    $key = $machkey->{"HARDWARE\\DEVICEMAP\\VIDEO"};
    # According to Q200435, Windows will load \Device\Video0
    my $keyname = $key->GetValue("\\Device\\Video0");
    $keyname =~ s/.*\\Services\\//;
    $key = $machkey->{"SYSTEM\\CurrentControlSet\\Services\\$keyname"};
    if (my $adapter = $key->{"HardwareInformation.AdapterString"}) {
        $adapter =~ s/\x00//g;
        $info->{"video_adapter"} = $adapter;
    }
    #my $description = $key->{"Device Description"}; # 2000 only?

    # Display Settings
    $key = $machkey->{"SYSTEM\\CurrentControlSet\\Hardware Profiles\\Current\\System\\CurrentControlSet\\Services\\$keyname"};
    my $xres = hex($key->{"DefaultSettings.XResolution"});
    my $yres = hex($key->{"DefaultSettings.YResolution"});
    my $bits = hex($key->{"DefaultSettings.BitsPerPel"});
    $info->{"display_resolution"} = $xres . "x" . $yres . "x". $bits;
    my $vref = hex($key->{"DefaultSettings.VRefresh"});
    $info->{"refresh_rate"} = "$vref Hz";

    # Hotfixes
    if (my $hotfixes = $machkey->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Hotfix"}) {
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

    if (my ($family, $model) =
        ($identifier =~ /^x86 Family (\d+) Model (\d+)/)) {

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

Win32::MachineInfo - Retrieve Windows NT/2000 OS and Hardware Info

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

Win32::MachineInfo is a module that retrieves OS, CPU, Memory, and Video
information from a remote Windows NT/2000 machine. It uses Win32::TieRegistry
to retrieve the information, which it returns as a hash structure.

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

=item $info->{'computer_name'}

=item $info->{'processor_vendor'}

=item $info->{'processor_name'}

=item $info->{'processor_speed'}

=item $info->{'memory'}

=item $info->{'system_bios_date'}

=item $info->{'system_bios_version'}

=item $info->{'video_bios_date'}

=item $info->{'video_bios_version'}

=item $info->{'video_adapter'}

=item $info->{'display_resolution'}

=item $info->{'refresh_rate'}

=item $info->{'osversion'}

=item $info->{'service_pack'}

=item $info->{'system_root'}

=item $info->{'install_date'}

=item $info->{'install_time'}

=item $info->{'registered_owner'}

=item $info->{'registered_organization'}

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
