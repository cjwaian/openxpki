
package OpenXPKI::Client::UI::Handle::Profile;

use Moose;
use Data::Dumper;
use English;
use OpenXPKI::Serialization::Simple;
use OpenXPKI::i18n qw( i18nGettext );

sub render_profile_select {

    my $class = shift; # static call
    my $self = shift; # reference to the wrapping workflow/result
    my $args = shift;
    my $wf_action = shift;


    $self->logger()->trace( 'render_profile_select with args: ' . Dumper $args );

    my $wf_info = $args->{wf_info};

    # Get the list of profiles from the backend - return is a hash with id => hash
    my $profiles = $self->send_command_v2( 'get_cert_profiles', {});
    # Transform hash into value/label list and sort it
    # Apply translation to sort on translated strings
    map { $profiles->{$_}->{label} = i18nGettext($profiles->{$_}->{label}) } keys %{$profiles};
    # Sort
    my @profiles = sort { lc($a->{label}) cmp lc($b->{label}) } values %{$profiles};

    my @profiledesc = map { $_->{description} ? { value => $_->{description}, label => $_->{label} } : () } @profiles;

    my $context = $wf_info->{workflow}->{context};

    my $cert_profile = $context->{cert_profile} || '';

    # If the profile is preselected, we need to fetch the options
    my @styles;
    if ($cert_profile) {
        my $styles = $self->send_command_v2( 'get_cert_subject_profiles', { profile => $cert_profile });
        my @styles = sort { lc($a->{label}) cmp lc($b->{label}) } values %{$styles};
    }

    my @fields;
    foreach my $field (@{$wf_info->{activity}->{$wf_action}->{field}}) {
        my $name = $field->{name};
        my $item = $self->__render_input_field( $field, $context->{$name} );

        if ($name eq 'cert_profile') {
            $item = {
                %{$item},
                options => \@profiles,
                actionOnChange => 'profile!get_styles_for_profile',
                prompt => $item->{placeholder}, # todo - rename in UI
            };
        } elsif ($name eq 'cert_subject_style') {
            $item = {
                %{$item},
                options => \@styles,
                prompt => $item->{placeholder}, # todo - rename in UI
            };
        }

        push @fields, $item;
    }


    # record the workflow info in the session
    push @fields, $self->__register_wf_token($wf_info, {
        wf_action => $wf_action,
        wf_fields => \@fields,
    });

    $self->add_section({
        type => 'form',
        action => 'workflow',
        content => {
            submit_label => 'I18N_OPENXPKI_UI_WORKFLOW_SUBMIT_BUTTON',
            fields => \@fields
        }
    });

    if (@profiledesc > 0) {
        $self->add_section({
            type => 'keyvalue',
            content => {
                label => 'I18N_OPENXPKI_UI_PROFILE_HINT_LIST',
                description => '',
                data => \@profiledesc
        }});
    }

    return $self;

}


sub render_subject_form {

    my $class = shift; # static call
    my $self = shift; # reference to the wrapping workflow/result
    my $args = shift;
    my $wf_action = shift;
    my $param = shift;

    my $section;
    my $mode = 'enroll';

    if ($param) {
        ($section, $mode) = split /!/, $param;
    }

    my $wf_info = $args->{wf_info};

    my $context = $wf_info->{workflow}->{context};

    # get profile and style from the context
    my $cert_profile = $context->{'cert_profile'};
    my $cert_subject_style = $context->{'cert_subject_style'};

    my $is_renewal = ($mode eq 'renewal');

    # Parse out the field name and type, we assume that there is only one activity with one field
    $wf_action = (keys %{$wf_info->{activity}})[0] unless($wf_action);
    my $field_name = $wf_info->{activity}->{$wf_action}->{field}[0]->{name};

    $section = substr($wf_info->{activity}->{$wf_action}->{field}[0]->{type}, 5) unless($section);

    $self->logger()->debug( " Render subject for $field_name, section $section in $wf_action" );

    # Allowed types are cert_subject, cert_san, cert_info
    my $fields = $self->send_command_v2( 'get_field_definition',
        { profile => $cert_profile, style => $cert_subject_style, 'section' =>  $section }
    );

    $self->logger()->trace( 'Profile fields' . Dumper $fields );

    # Load preexisiting values from context
    my $values = {};
    if ($context->{$field_name}) {
        $values = $self->serializer()->deserialize( $context->{$field_name} );
    }


    my @fielddesc;
    foreach my $field (@{$fields}) {
        push @fielddesc, { label => $field->{LABEL}, value => $field->{DESCRIPTION}, format => 'raw' } if ($field->{DESCRIPTION});
    }

    $self->logger()->trace( 'Preset ' . Dumper $values );

    # Map the old notation for the new UI
    $fields = OpenXPKI::Client::UI::Handle::Profile::__translate_form_def( $fields, $field_name, $values, $is_renewal );

    $self->logger()->trace( 'Mapped fields' . Dumper $fields );

    # record the workflow info in the session
    push @{$fields}, $self->__register_wf_token($wf_info, {
        wf_action => $wf_action,
        wf_fields => $fields,
    });

    $self->add_section({
        type => 'form',
        action => 'workflow',
        content => {
            submit_label => 'I18N_OPENXPKI_UI_WORKFLOW_SUBMIT_BUTTON',
            fields => $fields,
            buttons => $self->__get_form_buttons( $wf_info ),
        }
    });

    if (@fielddesc) {
        $self->add_section({
            type => 'keyvalue',
            content => {
                label => 'I18N_OPENXPKI_UI_WORKFLOW_FIELD_HINT_LIST',
                description => '',
                data => \@fielddesc
        }});
    }

    return $self;

}

sub render_key_select {

    my $class = shift; # static call
    my $self = shift; # reference to the wrapping workflow/result
    my $args = shift;
    my $wf_action = shift;

    $self->logger()->trace( 'render_profile_select with args: ' . Dumper $args );

    my $wf_info = $args->{wf_info};
    my $context = $wf_info->{workflow}->{context};

    # Get the list of allowed algorithms
    my $key_alg = $self->send_command_v2( 'get_key_algs', { profile => $context->{cert_profile} });
    my @key_type;
    foreach my $alg (@{$key_alg}) {
       push @key_type, { label => 'I18N_OPENXPKI_UI_KEY_ALG_'.uc($alg) , value => $alg };
    }

    my $key_gen_param_names = $self->send_command_v2( 'get_key_params', { profile => $context->{cert_profile} });

    # current values from context when changing values!
    my $key_gen_param_values = $context->{key_gen_params} ? $self->serializer()->deserialize( $context->{key_gen_params} ) : {};

    # Encryption
    my $key_enc = $self->send_command_v2( 'get_key_enc', { profile => $context->{cert_profile} });
    my @enc = map { { value => $_, label => 'I18N_OPENXPKI_UI_KEY_ENC_'.uc($_)  }  } @{$key_enc};

    my @fields;
    FIELDS:
    foreach my $field (@{$wf_info->{activity}->{$wf_action}->{field}}) {
        my $name = $field->{name};

        if ($name eq 'key_gen_params') {
            foreach my $pn (@{$key_gen_param_names}) {
                $pn = uc($pn);
                # We create the label as I18 string from the param name
                my $label = 'I18N_OPENXPKI_UI_KEY_'.$pn;
                push @fields, {
                    name => "key_gen_params{$pn}",
                    label => $label,
                    value => $key_gen_param_values->{ $pn },
                    type => 'select',
                    options => []
                };
            }
            next FIELDS;
        }

        my $item = $self->__render_input_field( $field );
        $item->{prompt} = $item->{placeholder}; # todo - rename in UI
        if ($name eq 'key_alg') {
            $item = {
                %{$item},
                options => \@key_type,
                actionOnChange => 'profile!get_key_param'
            };
        } elsif ($name eq 'enc_alg') {
            $item->{options} = \@enc;
        } elsif ($name eq 'csr_type') {
             $item->{value} = 'pkcs10';
        }
        push @fields, $item;
    }

    # record the workflow info in the session
    push @fields, $self->__register_wf_token($wf_info, {
        wf_action => $wf_action,
        wf_fields => \@fields,
        cert_profile => $context->{cert_profile}
    });

    $self->add_section({
        type => 'form',
        action => 'workflow',
        content => {
        submit_label => 'I18N_OPENXPKI_UI_WORKFLOW_SUBMIT_BUTTON',
            fields => \@fields
        }
    });

    return $self;

}

sub render_server_password {

    my $class = shift; # static call
    my $self = shift; # reference to the wrapping workflow/result
    my $args = shift;
    my $wf_action = shift;

    $self->logger()->trace( 'render_server_password with args: ' . Dumper $args );

    my $wf_info = $args->{wf_info};
    my $context = $wf_info->{workflow}->{context};

    my @fields;
    my $pwdfailed = 0;
    foreach my $field (@{$wf_info->{activity}->{$wf_action}->{field}}) {
        my $value;
        if ($field->{name} eq '_password') {
            $value = $self->send_command_v2( 'get_random', { length => 16 });
            if (!$value) {
                $self->set_status('I18N_OPENXPKI_UI_PROFILE_UNABLE_TO_GENERATE_PASSWORD_ERROR_LABEL','error');
                $self->add_section({
                    type => 'text',
                    content => {
                        label => 'I18N_OPENXPKI_UI_PROFILE_UNABLE_TO_GENERATE_PASSWORD_LABEL',
                        description => 'I18N_OPENXPKI_UI_PROFILE_UNABLE_TO_GENERATE_PASSWORD_DESC'
                    }
                });
                return $self;
            }
        } else {
            $value = $context->{$field->{name}};
        }
        my $item = $self->__render_input_field( $field, $value );
        push @fields, $item;
    }

    # record the workflow info in the session
    push @fields, $self->__register_wf_token($wf_info, {
        wf_action =>  (keys %{$wf_info->{activity}})[0],
        wf_fields => \@fields,
        cert_profile => $context->{cert_profile}
    });

    $self->add_section({
        type => 'form',
        action => 'workflow',
        content => {
        submit_label => 'I18N_OPENXPKI_UI_WORKFLOW_SUBMIT_BUTTON',
            fields => \@fields
        }
    });

    return $self;

}


sub __translate_form_def {

    my $fields = shift;
    my $field_name = shift;
    my $values = shift;
    my $is_renewal = shift || 0;

    # TODO - Refactor profile definitions to make this obsolete
    my @fields;
    foreach my $field (@{$fields}) {

        my $renew = $is_renewal ? ($field->{renew} || 'preset') : '';

        my $new = {
            name => $field_name.'{'.$field->{id}.'}',
            label => $field->{label},
            tooltip => defined $field->{tooltip} ? $field->{tooltip} : $field->{description},
             # Placeholder is the new attribute, fallback to old default
            placeholder => (defined $field->{placeholder} ? $field->{placeholder} : $field->{default}),
            value => $values->{$field->{id}},
        };

        if ($field->{type} eq 'freetext') {
            $new->{type} = 'text';
        } elsif ($field->{type} eq 'select') {
            $new->{type} = 'select';

            my @options;
            foreach my $item (@{$field->{options}}) {
               push @options, { label => $item, value => $item};
            }
            $new->{options} = \@options;
        } else {
            $new->{type} = 'text';
        }

        if (defined $field->{min}) {
            if ($field->{min} == 0) {
                $new->{is_optional} = 1;
            } else {
                $new->{min} = $field->{min};
                $new->{clonable} = 1;
            }
        }

        if (defined $field->{max}) {
            $new->{max} = $field->{max};
            $new->{clonable} = 1;
        }

        # Check for key/value field
        if ($field->{keys}) {
            $new->{name} =  $field_name.'{*}';
            my $format = $field_name.'{%s}';
            $format .= '[]' if ($new->{clonable});

            my @keys = map { {
                value => sprintf ($format, $_->{value}),
                label => $_->{label}
            } } @{$field->{keys}};
            $new->{keys} = \@keys;
        }

        if ($new->{clonable}) {
            $new->{name} .= '[]';
        }

        if ($renew eq 'clear') {
            $new->{value} = undef;

        } elsif ($renew eq 'keep') {
            $new->{type} = 'static';

        }

        push @fields, $new;

    }

    return \@fields;

}

1;

__END__
