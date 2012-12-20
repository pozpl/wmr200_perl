use Device::USB;
use Time::HiRes;

my $usb = Device::USB->new();
my $dev = $usb->find_device( 0x0fde, 0xca01);

printf "Device: %04X:%04X\n", $dev->idVendor(), $dev->idProduct();
print "Manufactured by ", $dev->manufacturer(), "\n",
      " Product: ", $dev->product(), "\n";

$dev->open();
if ($dev->get_driver_np(0, $namebuf, 256) == 0) {
	$dev->detach_kernel_driver_np(0);
}	

if ($dev->claim_interface(0) != 0) {
	printf "usb_claim_interface failed\n";
}
$dev->set_altinterface(0);

#$dev->set_configuration( $CFG );

send_init($dev);
receive_packet($dev);
send_ready($dev);
receive_packet($dev);
send_command($dev,0xDF);
receive_packet($dev);
send_command($dev, 0xDA);
receive_packet($dev);
send_command($dev, 0xD3);
receive_packet($dev);

while(1){
	send_command($dev, 0xD0);
	my @frame = read_frame($dev);
	print_byte_array(\@frame);
	sleep(3);	
}


#close session 
send_command($dev, 0xDF);
close_ws($dev);
   

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
# Usage      : @frame_octets_array = read_frame($dev); 
# Purpose    : read frame of viriety length from device
# Returns    : array of octets, that represents device responce
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : read_packet function definition
sub read_frame($){
	my ($dev) = @_;
	
	my @packet = receive_packet($dev);
	my @frame;
	while($packet[0] > 0){
		my @packet_reduced = @packet;
		my @meaningful_data = splice(@packet_reduced, 1, $packet[0] + 1);
		push(@frame, @meaningful_data);
		@packet = receive_packet($dev);
	}
	return @frame;
} 

############################################
# Usage      : @packet_bytes = read_packet($dev); 
# Purpose    : aptain one packet of 32 bytes length from a device
# Returns    : array of octets, that represents device responce
# Parameters : device handler
# Throws     : no exceptions
# Comments   : n/a
# See Also   : read_frame function definition
sub receive_packet($){
	my ($dev) = @_;
	my $count = $dev->interrupt_read( 0x81, $buf = "", 8, 1000 );
	if($count > 0){
	 	print_bytes($buf, $count);
	 	my @bytes = unpack("C$count", $buf);
	 	return @bytes;
	}else{
		return ();
	}	
}


sub print_bytes($) {
	my $buf = shift;
	my $len = shift;
   
	if ($len <= 0) {
		return;
	}
	my @bytes = unpack("C$len", $buf);

    	if ($len > 0) {
        	for (my $i=0; $i<$len; $i++) {
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
sub print_byte_array($){
	my ($bytes_array_ref) = @_;
	
	if(@{$bytes_array_ref}){
		foreach my $byte (@{$bytes_array_ref}){
			printf "%02x ", $bytes[$i];
		}
	}
}

sub send_command($$){
	my($dev, $command) = @_;
	my @params = (0x01, $command, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	print $command . "\n";
	my $tbuf = pack('CCCCCCCC', @params);
	my $retval = send_packet($dev, $tbuf);
	print "Commmand retval $retval \n";
}

sub send_packet($$){
	my($dev, $packet) = @_;
	print $command . "\n";
	my $tbuf = pack('CCCCCCCC', @$packet);
	my $retval = $dev->control_msg(0x21, 9, 0x200, 0, $tbuf, 8, 1000);
	return $retval;
}

sub send_init($){
	my ($buf) = @_;
	my @packet = (0x20, 0x00, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00);
	my $retval = send_packet($dev, \@packet);
	print "Init retval $retval \n";
	
}

sub send_ready($){
	my ($buf) = @_;
	my @packet = (0x01, 0xd0, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00 );
	my $retval = send_packet($dev, \@packet);
	print "Ready retval $retval \n";
}
