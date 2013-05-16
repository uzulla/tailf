package TailF::Controller::Facebook;
use Sub::Retry;
use JSON qw/encode_json decode_json/;
use Data::Dumper;

sub on_auth_finished {
  my ( $c, $access_token, $account_info ) = @_;
  $c->app->log->debug("Facebook API response :".Dumper($account_info));

  my $user = $c->db->single('user_account', +{facebook_id=> $account_info->{id}});
  unless($user){
    $c->app->log->info("new user account Facebook:".$account_info->{id});
    my $res = $c->db->insert('user_account', +{ 
      name => $account_info->{name}, 
      facebook_token => $access_token,
      facebook_id => $account_info->{id}, 
      avatar_img_url => "http://graph.facebook.com/$account_info->{id}/picture", 
      created_at=>0,
      updated_at=>0 
      } );
    $user = $c->db->single('user_account', +{facebook_id=> $account_info->{id}});
  }

  $c->stash('session')->data('user'=>$user->get_columns);
  $c->app->log->info("logged in ".$account_info->{name}." by Facebook");
  $c->redirect_to('/mypage/facebook');
}

sub mypage  {
    my $self = shift;
    my $user = $self->stash('session')->data('user');
    my @facebook_photo_list = $self->db->search('facebook_photo',
      +{ facebook_user_id => $user->{facebook_id} },
      +{ limit => 10_000, order_by => 'created_time DESC' }
      );
    $self->stash(facebook_photo_list => \@facebook_photo_list);    
    return $self->render
};

sub update_photo {
    my $FACEBOOK_LIMIT_NUM = 1000;
    my $FACEBOOK_HARD_LIMIT_NUM = 5000;

    my $self = shift;

    my $user = $self->stash('session')->data('user');
    unless($user->{facebook_id}){
      $self->redirect_to('/');
      return;
    }

    my $_user = $self->db->single('user_account', +{id=> $user->{id}});

    my $f = new Furl;

    my $uri = URI->new("https://graph.facebook.com");
    $uri->path( 'fql' );

    my @newest_facebook_photo = $self->db->search('facebook_photo',
      +{ facebook_user_id => $user->{facebook_id} },
      +{ limit => 1, order_by => 'created_time DESC' }
      );

    my $newest_facebook_photo_created = $newest_facebook_photo[0] ? $newest_facebook_photo[0]->created_time : 0 ;
    my $offset = 0;
    while (1) {
      $self->app->log->debug("START get data Facebook API URL");
      $uri->query_form(
        access_token => $_user->facebook_token,
        encode => "json",
        q => "
          SELECT object_id,src,src_height,src_width,src_big,src_big_height,src_big_width,created,modified 
          FROM photo 
          WHERE owner = me() AND created > $newest_facebook_photo_created
          ORDER BY created
          LIMIT $FACEBOOK_LIMIT_NUM 
          OFFSET $offset
        "
        );

      my $res = retry 3, 2, sub {
        $self->app->log->debug('try facebook :'.$uri->as_string);
        $f->get($uri);
      }, sub {
        my $res = shift;
        $res->is_success ? 0 : 1;
      } ;

      unless($res){
        $self->app->log->warn("Facebook request error give up");
        last;
      }

      $self->app->log->debug("facebook api res:" . Dumper(decode_json($res->content)));

      my $search_result = decode_json($res->content);
      last if scalar(@{$search_result->{data}}) < 1 ;

      foreach my $i (@{$search_result->{data}}) {
        unless( $self->db->single('facebook_photo', +{'facebook_object_id'=>$i->{object_id}} ) ){
          $self->app->log->debug("save img $i->{src}");
          my $res = $self->db->insert('facebook_photo', +{ 
            facebook_user_id => $_user->facebook_id,
            facebook_object_id => $i->{object_id},
            img_std_url => $i->{src_big},
            img_std_size => $i->{src_big_width}."x".$i->{src_big_height},
            img_tmb_url => $i->{src},
            img_tmb_size => $i->{src_width}."x".$i->{src_height},
            created_time => $i->{created},
            modified_time => $i->{modified},
            created_at=>0,
            updated_at=>0 
            } );
        }else{
          $self->app->log->warn("try save dup img. $i->{images}->{thumbnail}->{url}. skipped");
        }

      }

      $offset = $offset +$FACEBOOK_LIMIT_NUM ;
      last if $offset > $FACEBOOK_HARD_LIMIT_NUM;
    };

    return $self->render_json({status=>'ok'});
}

1;