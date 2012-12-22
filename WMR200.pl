use Device::USB;
use Time::HiRes;

#my $usb = Device::USB->new();
#my $dev = $usb->find_device( 0x0fde, 0xca01 );
#
#printf "Device: %04X:%04X\n", $dev->idVendor(), $dev->idProduct();
#print "Manufactured by ", $dev->manufacturer(), "\n", " Product: ", $dev->product(), "\n";
#
#$dev->open();
#if ( $dev->get_driver_np( 0, $namebuf, 256 ) == 0 ) {
#	$dev->detach_kernel_driver_np(0);
#}
#
#if ( $dev->claim_interface(0) != 0 ) {
#	printf "usb_claim_interface failed\n";
#}
#$dev->set_altinterface(0);

my $dev = connect_to_device();

#send_init($dev);
#receive_packet($dev);
#send_ready($dev);
#receive_packet($dev);
#send_command( $dev, 0xDF );
#receive_packet($dev);
#send_command( $dev, 0xDA );
#receive_packet($dev);
#send_command( $dev, 0xD3 );
#receive_packet($dev);

while (1) {
    send_command( $dev, 0xD0 );
    my @frame = read_frame($dev);
    print_byte_array( \@frame );
    sleep(3);
}

#close session
connect_to_device($dev);

##
## Close the connection to the Weather Station & exit
##
sub close_ws($) {
    my ($dev) = @_;
    $dev->release_interface(0);
    undef $dev;
    exit;
}

############################################
# Usage      : connect_to_device();
# Purpose    : identify and connec to a device and send init sequences to open a session
#              for data handling
# Returns    : device handler ready to data interchange
# Parameters : none
# Throws     : no exceptions
# Comments   : n/a
# See Also   : n/a
sub connect_to_device($) {
    my $usb = Device::USB->new();
    my $dev = $usb->find_device( 0x0fde, 0xca01 );

    printf "Device: %04X:%04X\n", $dev->idVendor(), $dev->idProduct();
    print "Manufactured by ", $dev->manufacturer(), "\n",
      " Product: ", $dev->product(), "\n";

    print "Open device...  ";
    $dev->open();
    if ( $dev->get_driver_np( 0, $namebuf, 256 ) == 0 ) {
        $dev->detach_kernel_driver_np(0);
    }

    if ( $dev->claim_interface(0) != 0 ) {
        printf "usb_claim_interface failed\n";
        return 0;
    }
    $dev->set_altinterface(0);
    print "done\n";
    
    print "Send init sequence...";
    send_init($dev);
    clear_recevier($dev);
    print "done\n";
    print "Send ready sequence...";
    send_ready($dev);
    clear_recevier($dev);
    print "done\n";
    print "Cancel all previous device PC connections...";
    send_command( $dev, 0xDF );
    clear_recevier($dev);
    print "done\n";
    print "Send hello packet...";
    send_command( $dev, 0xDA );
    @hello_packet = receive_packet($dev);
    if ( @hello_packet = 0 ) {
        print "error no responce\n";
        return 0;
    }
    elsif ( $hello_packet[0] == 0x01 && $hello_packet[1] == 0xD1 ) {
        print "Station identified\n";
    }else{
        print "error bad hello response\n";
    }
    clear_recevier($dev);
    print "\nUSB connected\n";
    return $dev;
}

############################################
# Usage      : diconnect_from_device();
# Purpose    : diconnect from device
# Returns    : none
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : n/a
sub diconnect_from_device($) {
    my ($dev) = @_;
    eval {
        send_command($dev, 0xDF);
        close_ws($dev);
    };
}

############################################
# Usage      : clear_recevier($dev);
# Purpose    : draw all data from device buffers to get clean input sequence during a data
#				receive process
# Returns    : none
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : read_packet function definition
sub clear_recevier($) {
    my ($dev) = @_;
    my $packet = receive_packet($dev);
    while ( $packet[0] > 0 ) {
        $packet = receive_packet($dev);
    }
}

############################################
# Usage      : @frame_octets_array = read_frame($dev);
# Purpose    : read frame of viriety length from device
# Returns    : array of octets, that represents device responce
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : read_packet function definition
sub read_frame($) {
    my ($dev) = @_;

    my @packet = receive_packet($dev);
    my @frame;
    while ( $packet[0] > 0 ) {
        my @packet_reduced = @packet;
        my @meaningful_data = splice( @packet_reduced, 1, $packet[0] + 1 );
        push( @frame, @meaningful_data );
        @packet = receive_packet($dev);
    }
    return @frame;
}


sub receive_frames($){
    my ($dev) = @_;
    
    #draw all data from the device
    my @packet = receive_packet($dev);
    my @packets;
    while ( $packet[0] > 0 ) {
        my @packet_reduced = @packet;
        my @meaningful_data = @packet[ 1,  $packet[0] + 1 ];
        push( @packets, @meaningful_data );
        @packet = receive_packet($dev);
    }
    #print_byte_array(@packets);
    
    my @frames;
    #pick up frames from the packets obtained from the device
    while(1){
        if ($packets[0] < 0xD1 || $packets[0] > 0xD9){
            print "bad input sequence frames first elements mast be in [0xD1, 0xD9] interval\n";
            last;
        }
        if($packets[0] == 0xD1 && @packets == 1){
            #oh man we have only on octet here
            @frame = (0xD1);
            push (@frames, \@frame);
        }elsif(@packets < 2 || @packets < $packets[1]){
            #something wrontg with a frame we have, it has length less then in packets[1], 
            #so this is bad packet
            print "Packet lenght is less than in $packets[1]\n";
            last;
        }elsif(@packets < 8){
            #packet length mas be no less than 8
            print "Packet lenght is less than 8\n";
            last;
        }else{
            #get frame
            my @frame = @packets[0, $#packets + 1];
            #trancate packets sequence
            @packets = @packets[$packets[1], @packets];
            
            #validate frame with checksumm
            # The last 2 octets of D2 - D9 frames are always the low and high byte
            # of the checksum. We ignore all frames that don't have a matching
            # checksum.
            if(! validate_check_summ(\@frame[0, @frame - 2],  $frame[@frame -2] | $frame[@frame - 1] << 8)){
                print "Frame checksumm is broken\n";
                last;
            }
        }
    }
    
    return @frame;
        
}
############################################
# Usage      : $is_valid = validate_check_summ(\@frame[0, @frame - 2],  $frame[@frame -2] | $frame[@frame - 1] << 8);
# Purpose    : check frame with checksumm
# Returns    : true if frame is ok and false otherwise
# Parameters : frame to check, check summ
# Throws     : none
# Comments   : n/a
# See Also   : 
sub validate_check_summ($$){
    my ($packet_ref, $check_summ) = @_;
    my $sum = 0;
    foreach my $byte (@$packet_ref){
        $sum += $byte;
    }
    if($sum == $check_summ){
        return 1;
    }else{
        return 0;
    }    
}

sub getData($) {
    my ($dev) = @_;

    while (1) {
        send_command( $dev, 0xD0 );
        my @frame = read_frame($dev);
        print_byte_array( \@frame );
        sleep(3);
    }
}

############################################
# Usage      : @packet_bytes = read_packet($dev);
# Purpose    : aptain one packet of 32 bytes length from a device
# Returns    : array of octets, that represents device responce
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : read_frame function definition
sub receive_packet($) {
    my ($dev) = @_;
    my $count = $dev->interrupt_read( 0x81, $buf = "", 8, 1000 );
    if ( $count > 0 ) {
        #		print_bytes( $buf, $count );
        my @bytes = unpack( "C$count", $buf );
        return @bytes;
    }
    else {
        return ();
    }
}

sub print_bytes($) {
    my $buf = shift;
    my $len = shift;

    if ( $len <= 0 ) {
        return;
    }
    my @bytes = unpack( "C$len", $buf );

    if ( $len > 0 ) {
        for ( my $i = 0 ; $i < $len ; $i++ ) {
            printf "%02x ", $bytes[$i];
        }
    }
    printf "\n";
}

############################################
# Usage      : print_byte_array(\@byte_array);
# Purpose    : print contents of a byte array
# Returns    : non
# Parameters : byte array reference
# Throws     : no exceptions
# Comments   : n/a
# See Also   : print_bytes function defenition
sub print_byte_array($) {
    my ($bytes_array_ref) = @_;

    if ( @{$bytes_array_ref} ) {
        foreach my $byte ( @{$bytes_array_ref} ) {
            printf "%02x ", $bytes[$i];
        }
        print "\n";
    }
}

############################################
# Usage      : send_command($device, 0XDA);
# Purpose    : send command to the device.
# Returns    : command execution status
# Parameters : device handeler
#              command octet
# Throws     : no exceptions
# Comments   : n/a
# See Also   : read_frame function defenition
sub send_command($$) {
    my ( $dev, $command ) = @_;
    my @params = ( 0x01, $command, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 );
    my $tbuf = pack( 'CCCCCCCC', @params );
    my $retval = send_packet( $dev, $tbuf );
    #print "Commmand retval $retval \n";
    return $retval;
}

sub send_packet($$) {
    my ( $dev, $packet ) = @_;
    print $command . "\n";
    my $tbuf = pack( 'CCCCCCCC', @$packet );
    my $retval = $dev->control_msg( 0x21, 9, 0x200, 0, $tbuf, 8, 1000 );
    return $retval;
}

sub send_init($) {
    my ($dev) = @_;
    my @packet = ( 0x20, 0x00, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00 );
    my $retval = send_packet( $dev, \@packet );
    return $retval;

}

sub send_ready($) {
    my ($dev) = @_;
    my @packet = ( 0x01, 0xd0, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00 );
    my $retval = send_packet( $dev, \@packet );
    return $retval;
}
