package CFE::TOLOT::PhotoBook;
use Mouse;
use FurlX::Coro;
use Coro;
use Coro::Semaphore;
use Carp 'croak';
use File::Temp qw/tempfile/;
use Archive::Zip;
use Data::Dumper;
use XML::Simple;
use Encode;

has image_file_list => (
    is  => "rw",
    isa => 'ArrayRef[Str]',
    default => sub { [] },
);
has book_title => (
    is  => "rw",
    isa => "Str",
    default => sub { 'Undefined title' },
);
has sub_title => (
    is  => "rw",
    isa => "Str",
    default => sub { '' },
);
has temporary_dir => (
    is => "ro",
    isa => "Str",
    required => 1,
);
has zip_output_dir => (
    is => "ro",
    isa => "Str",
    required => 1,
);

has data_base_dir => (
    is => "ro",
    isa => "Str",
    required => 1,
);

has debug =>(
    is => "rw",
    isa => "Bool",
    default => sub { 1 },
);

has check_img_num =>(
    is => "rw",
    isa => "Bool",
    default => sub { 1 },
);

sub set_image_file_list_by_url_list {
    my ($self, @url_list) = @_;

    die "TOLOT photo book must be 62p" unless ( !$self->check_img_num || scalar(@url_list) == 62 );

    warn "get_images_by_url_list \n" . join("\n", @url_list) if $self->debug;

    my @coros;
    my $semaphore = Coro::Semaphore->new(4); # 4 並列まで
    my $ua = FurlX::Coro->new(timeout => 10);
    my @tmp_filename_list = ();

    foreach my $img (@url_list){
      push @coros, async {
        my $guard = $semaphore->guard;
        my $response = $ua->get($img);
        if ($response->is_success) {
          my $idx =  List::MoreUtils::firstidx { $_ eq $img } @url_list;
          warn "download success -> $idx: $img" if $self->debug;

          my ($fh, $filename) = tempfile('img_XXXX', DIR => $self->temporary_dir);
          $tmp_filename_list[$idx] = $filename;
          print $fh $response->decoded_content;
          close $fh;
        } else {
          die "File download fail $response->status_line : $img";
        }
      }
    }
    $_->join for @coros; # wait done.
    warn "download complete." if $self->debug;

    $self->image_file_list(\@tmp_filename_list);
}

sub create_zip{
    my ($self) = @_;

    # make zip
    my $zip = Archive::Zip->new();

    # create dir.
    $zip->addDirectory('tolot/OEBPS/');
    $zip->addDirectory('tolot/OEBPS/images/');
    $zip->addDirectory('tolot/OEBPS/texts/');
    $zip->addDirectory('tolot/OEBPS/tolot/');

    # add meta data
    $zip->addFile( $self->data_base_dir."/content.opf", 'tolot/OEBPS/content.opf');
    $zip->addFile( $self->data_base_dir."/info.xml", 'tolot/OEBPS/tolot/info.xml');

    # add page data.
    my $image_file_num = scalar(@{$self->image_file_list}) - 1;
    for(0..$image_file_num){
      $zip->addFile( $self->data_base_dir."/texts/page$_.xhtml", "tolot/OEBPS/texts/page$_.xhtml");
      $zip->addFile( $self->image_file_list->[$_+0], "tolot/OEBPS/images/$_.jpg");
    }

    # create meta data.
    my $book_xml = XMLin($self->data_base_dir."/book.xml");
    $book_xml->{title} = $self->book_title;
    $book_xml->{subTitle} = $self->sub_title;
    my @theme_code_list = List::Util::shuffle(
        "5121","5122","5123","5124","5125","5126","5127","5128","5129","5130","5131","5132",
        "6145","6146","6147","6148","6149","6150","6151","6152"
    );
    $book_xml->{themeCode} = $theme_code_list[0];
    $zip->addString( 
        encode('utf-8', XMLout( $book_xml, NoAttr=>1, RootName=>'book', XMLDecl=>"<?xml version='1.0' encoding='UTF-8'?>" )),
        'tolot/OEBPS/tolot/book.xml'
    );

    # output zip 
    my $temporary_zip_filename = sub{join"",map{$_[rand@_]}1..40}->("a".."z",0..9,"A".."Z") . ".tlt";
    my $temporary_zip_path = $self->zip_output_dir."/$temporary_zip_filename";
    open my $zipfh, ">", $temporary_zip_path;
    $zip->writeToFileHandle($zipfh, 0);
    close $zipfh;

    # cleaning
    foreach my $filename (@{$self->image_file_list}){
      unlink $filename or die "delete file fail $filename";
    }

    #return zip file name
    return $temporary_zip_filename;
}

1;
