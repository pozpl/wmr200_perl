use Device::USB;
use Time::HiRes;
use DateTime;

while (1) {
    my $dev = connect_to_device();
    while ( !$dev ) {
        $dev = connect_to_device();
        sleep(3);
    }

    get_data($dev);

    #close session
    disconnect_from_device($dev);
}

##
## Close the connection to the Weather Station & exit
##
sub close_ws($) {
    my ($dev) = @_;
    $dev->release_interface(0);
    undef $dev;
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

    #    clear_recevier($dev);
    print "done\n";
    print "Send ready sequence...";
    send_ready($dev);

    #    clear_recevier($dev);
    print "done\n";
    print "Cancel all previous device PC connections...";
    send_command( $dev, 0xDF );

    #    clear_recevier($dev);
    print "done\n";
    print "Send hello packet...";
    send_command( $dev, 0xDA );
    my @hello_packet = receive_packet($dev);

    if ( @hello_packet == 0 ) {
        print "error no responce\n";
        return 0;
    }
    elsif ( $hello_packet[0] == 0x01 && $hello_packet[1] == 0xD1 ) {
        print "Station identified\n";
    }
    else {
        print "error bad hello response\n";
        return 0;
    }

    #    clear_recevier($dev);
    print "\nUSB connected\n";
    return $dev;
}

############################################
# Usage      : disconnect_from_device();
# Purpose    : disconnect from device
# Returns    : none
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : n/a
sub disconnect_from_device($) {
    my ($dev) = @_;
    eval {
        send_command( $dev, 0xDF );
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

sub decode_frame($) {
    my ($frame_ref) = @_;

    my $frame_type = ${$frame_ref}[0];
    if ( $frame_type == 0xD2 ) {

        #Historic data reccord
    }
}

sub decode_timestamp($) {
    my ($timestamp_ref) = @_;

    my $minutes      = ${$timestamp_ref}[0];
    my $hours        = ${$timestamp_ref}[1];
    my $day_of_month = ${$timestamp_ref}[2];
    $day_of_month = $day_of_month == 0 ? 1 : $day_of_month;
    my $month     = ${$timestamp_ref}[3];
    my $year      = 2000 + ${$timestamp_ref}[4];
    my $date_time = DateTime->new(
        year      => $year,
        month     => $month,
        day       => $day_of_month,
        hour      => $hours,
        minute    => $minutes,
        time_zone => 'Asia/Vladivostok',
    );

    return $date_time;
}

############################################
# Usage      : my ($rain_rate, $rain_total, $date_of_mesurment_start, $rain_hour, $rain_day) =
#              decode_rain(\@frame[7,19]);
# Purpose    : read rain parameters
# Returns    : rain rate, rain total since begining of mesurments start, data of mesurment start,
#               rain in hour, rain in day
# Parameters : reference to rain part of freame
# Throws     : no exceptions
# Comments   : n/a
# See Also   : none
sub decode_rain($) {
    my ($rain_ref) = @_;

    # Bytes 0 and 1: high and low byte of the current rainfall rate
    # in 0.1 in/h
    my $rain_rate = ( ( ${$rain_ref}[1] << 8 ) | ${$rain_ref}[0] ) / 3.9370078;

    # Bytes 2 and 3: high and low byte of the last hour rainfall in 0.1in
    my $rain_hour = ( ( ${$rain_ref}[3] << 8 ) | ${$rain_ref}[2] ) / 3.9370078;

    # Bytes 4 and 5: high and low byte of the last day rainfall in 0.1in
    my $rain_day = ( ( ${$rain_ref}[5] << 8 ) | ${$rain_ref}[4] ) / 3.9370078;

    # Bytes 6 and 7: high and low byte of the total rainfall in 0.1in
    my $rain_total = ( ( ${$rain_ref}[7] << 8 ) | ${$rain_ref}[6] ) / 3.9370078;

    # Bytes 8 - 12 contain the time stamp since the measurement started.
    my $date_of_mesurment_start = decode_timestamp( \@{$rain_ref}[ 8, 12 ] );
    return ( $rain_rate, $rain_total, $date_of_mesurment_start, $rain_hour, $rain_day );
}

############################################
# Usage      : my ($wind_direction_degries, $avg_speed, $gust_speed, $windchill) = decode_wind(\@frame[20, 26]);
# Purpose    : decode wind part of the frame
# Returns    : list consits of wind derection, avg speed, gust speed, wind chill
#               all parameters given in corresponding order
# Parameters : reference to the wind part of a frame
# Throws     : no exceptions
# Comments   : n/a
# See Also   : none
sub decode_wind($) {
    my ($wind_ref) = @_;

    $wind_direction_degries = ( ${$wind_ref}[0] & 0xF ) * 22.5;
    $gust_speed = ( ( ( ( ${$wind_ref}[1] >> 4 ) & 0xF ) << 8 ) | ${$wind_ref}[2] ) * 0.1;
    $avg_speed = ( ( ${$wind_ref}[4] << 4 ) | ( ( ${$wind_ref}[3] >> 4 ) & 0xF ) ) * 0.1;

    if ( ${$wind_ref}[5] != 0 or ${$wind_ref}[6] != 0x20 ) {
        $windchill =
          ( ( ( ${$wind_ref}[6] << 8 ) | ${$wind_ref}[5] ) - 320 ) * ( 5.0 / 90.0 );
    }
    else {
        $windchill = 0;
    }

    #    def decodeWind(self, record):
    #      # Byte 0: Wind direction in steps of 22.5 degrees.
    #      # 0 is N, 1 is NNE and so on. See windDirMap for complete list.
    #      dirDeg = (record[0] & 0xF) * 22.5
    #      # Byte 1: Always 0x0C? Maybe high nible is high byte of gust speed.
    #      # Byts 2: The low byte of gust speed in 0.1 m/s.
    #      gustSpeed = ((((record[1] >> 4) & 0xF) << 8) | record[2]) * 0.1
    #      if record[1] != 0x0C:
    #        self.logger.info("TODO: Wind byte 1: %02X" % record[1])
    #      # Byte 3: High nibble seems to be low nibble of average speed.
    #      # Byte 4: Maybe low nibble of high byte and high nibble of low byte
    #      #          of average speed. Value is in 0.1 m/s
    #      avgSpeed = ((record[4] << 4) | ((record[3] >> 4) & 0xF)) * 0.1
    #      if (record[3] & 0x0F) != 0:
    #        self.logger.info("TODO: Wind byte 3: %02X" % record[3])
    #      # Byte 5 and 6: Low and high byte of windchill temperature. The value is
    #      # in 0.1F. If no windchill is available byte 5 is 0 and byte 6 0x20.
    #      # Looks like OS hasn't had their Mars Climate Orbiter experience yet.
    #      if record[5] != 0 or record[6] != 0x20:
    #        windchill = (((record[6] << 8) | record[5]) - 320) * (5.0 / 90.0)
    #      else:
    #        windchill = None
    #
    #      self.logger.info("Wind Dir: %s" % windDirMap[record[0]])
    #      self.logger.info("Gust: %.1f m/s" % gustSpeed)
    #      self.logger.info("Wind: %.1f m/s" % avgSpeed)
    #      if windchill != None:
    #        self.logger.info("Windchill: %.1f C" % windchill)
    #
    #      return (dirDeg, avgSpeed, gustSpeed, windchill)
    return ( $wind_direction_degries, $avg_speed, $gust_speed, $windchill );

}

############################################
# Usage      : my @frames_array = receive_frames($dev);
# Purpose    : perform on session of frames receiving from a device
# Returns    : array of frames obtained from a device
# Parameters : $device handler object
# Throws     : no exceptions
# Comments   : n/a
# See Also   : none
sub receive_frames($) {
    my ($dev) = @_;

    #draw all data from the device
    my @packet = receive_packet($dev);
    my @packets;
    while ( $packet[0] > 0 ) {
        my @packet_reduced = @packet;
        my @meaningful_data = @packet[ 1, $packet[0] + 1 ];
        push( @packets, @meaningful_data );
        @packet = receive_packet($dev);
    }
    if ( @packets == 0 ) {

        #we do not receive anything its, bad
        print "Empty input\n";
        return ();
    }
    print "RECEIVED PACKETS ";
    print_byte_array( \@packets );

    my @frames;

    #pick up frames from the packets obtained from the device
    while (1) {
        if ( $packets[0] < 0xD1 || $packets[0] > 0xD9 ) {
            print
"bad input sequence frames first elements mast be in [0xD1, 0xD9] interval\n";
            last;
        }
        if ( $packets[0] == 0xD1 && @packets == 1 ) {

            #oh man we have only on octet here
            @frame = (0xD1);
            push( @frames, \@frame );
        }
        elsif ( @packets < 2 || @packets < $packets[1] ) {

            #something wrontg with a frame we have, it has length less then in packets[1],
            #so this is bad packet
            print "Packet lenght is less than in $packets[1]\n";
            last;
        }
        elsif ( $packets[1] < 8 || @packets < 8 ) {

            #packet length mas be no less than 8
            print "Packet lenght is less than 8\n";
            last;
        }
        else {
            $bytes_langth = @packets;
            print "BYTES LANGTH $bytes_langth\n";

            #get frame
            my @frame = @packets[ 0, $packets[1] ];
            my $frame_length = $packets[1];

            #trancate packets sequence
            @packets = @packets[ $packets[1], @packets ];

            #validate frame with checksumm
            # The last 2 octets of D2 - D9 frames are always the low and high byte
            # of the checksum. We ignore all frames that don't have a matching
            # checksum.
            my @validate_part = \@frame[ 0, @frame - 3 ];
            if (
                !validate_check_summ(
                    \@validate_part, $frame[ @frame - 2 ] | $frame[ @frame - 1 ] << 8
                )
              )
            {
                print "Frame checksumm is broken\n";
                last;
            }

            push( @frames, \@frame );
        }
    }

    return @frames;

}
############################################
# Usage      : $is_valid = validate_check_summ(\@frame[0, @frame - 2],  $frame[@frame -2] | $frame[@frame - 1] << 8);
# Purpose    : check frame with checksumm
# Returns    : true if frame is ok and false otherwise
# Parameters : frame to check, check summ
# Throws     : none
# Comments   : n/a
# See Also   :
sub validate_check_summ($$) {
    my ( $packet_ref, $check_summ ) = @_;
    my $sum = 0;
    foreach my $byte ( @{$packet_ref} ) {
        $sum += $byte;
    }
    if ( $sum == $check_summ ) {
        return 1;
    }
    else {
        return 0;
    }
}

############################################
# Usage      : get_data($dev);
# Purpose    : run permanent cycle to get frames and do something with them
# Returns    : none
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : read_frame function definition
sub get_data($) {
    my ($dev) = @_;

    my $empty_frames_tryes = 0;
    while (1) {
        send_command( $dev, 0xD0 );
        my @frames = receive_frames($dev);
        foreach $frame_ref (@frames) {
            print_byte_array( \@frame );
        }
        if ( @frames == 0 ) {
            $empty_frames_tryes += 1;
            if ( $empty_frames_tryes >= 20 ) {
                last;
            }
        }
        else {
            $empty_frames_tryes = 0;
        }

        sleep(5);
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
    my $read_errors = 0;
    while (1) {
        my $count = $dev->interrupt_read( 0x81, $buf = "", 8, 2000 );
        if ( $count > 0 ) {
            my @bytes = unpack( "C$count", $buf );
            if ( $count != 8 ) {
                print "bad packet length > 8";
                $read_errors++;
                next;
            }
            elsif ( $bytes[0] > 7 ) {
                print "length of minigfull data > 7";
                $read_errors++;
                next;
            }else{
                return @bytes;
            }
        }else{
            $read_errors++;
        }
        
        if($read_errors > 20){
            last;
        }
    }
    
    return ();
    
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

    if ( @{$bytes_array_ref} > 0 ) {
        foreach my $byte ( @{$bytes_array_ref} ) {
            printf "%02x ", $byte;
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
