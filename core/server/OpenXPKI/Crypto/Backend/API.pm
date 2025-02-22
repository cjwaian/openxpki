## OpenXPKI::Crypto::Backend::API
## Written 2006 by Michael Bell for the OpenXPKI project
## Converted to use Class::Std and OpenXPKI::Crypto::API
## 2006 by Alexander Klink for the OpenXPKI project
## (C) Copyright 2006 by The OpenXPKI Project
package OpenXPKI::Crypto::Backend::API;
use base qw( OpenXPKI::Crypto::API );

use strict;
use warnings;

use Class::Std;
use OpenXPKI::Debug;
use OpenXPKI::Exception;
use OpenXPKI::Server::Context qw( CTX );
use Data::Dumper;
use English;
#use Smart::Comments;

## scalar value:
##     - 0 means the parameter is optional
##     - 1 means the parameter is required
## array values:
##     - an array represent the allowed parameters
##     - element "__undef" in the array means that the parameter is optional
## hash values:
##     - "" => {...} (these are the default parameters
##     - "TYPE:EC" => {...} means parameters if TYPE => "EC" is used


my %object_cache_of :ATTR; # the object cache attribute

sub __init_command_params : PRIVATE {
    ##! 16: 'start'
    my $self = shift;

    ## application of the crypto layer policy: names of crypto algorithms should be defined in the crypto backend
    ## now implemented for the public key algoriths only

    ## define params for all the crypto commands
    my $command_params = {
    "list_algorithms" => {"FORMAT"        => 1,
                          "ALG"           => 0,
                          "PARAM"         => 0},
    "convert_cert"    => {"DATA"             => 1,
                          "IN"               => ["DER", "PEM"],
                          "OUT"              => ["DER","TXT","PEM","TXTPEM"],
                          "CONTAINER_FORMAT" => 0,
                          },
    "convert_crl"     => {"DATA" => 1,
                          "IN"   => ['DER', 'PEM'],
                          "OUT"  => ['DER', 'PEM', 'TXT']},
    "convert_pkey"     => {"PASSWD"     => 1,
                          "OUT_PASSWD" => 0,
                          "NOPASSWD"       => ["__undef",0,1],
                          "ENC_ALG"    => ["__undef", "aes256","aes192","aes128","idea","des3","des"],
                          "KEYTYPE"    => ["pkey","rsa"],
                          "IN"         => ["PEM","DER"],
                          "OUT"        => ["PEM","DER"],
                          "DATA"       => 1,
                         },
    "convert_pkcs8"   => {
                          "PASSWD"     => 1,
                          "OUT_PASSWD" => 0,
                          "NOPASSWD"       => ["__undef",0,1],
                          "ENC_ALG"    => ["__undef", "aes256","aes192","aes128","idea","des3","des"],
                          "IN"         => ["PEM","DER"],
                          "OUT"        => ["PEM","DER"],
                          "DATA"       => 1,
                          "REVERSE"    => 1
                         },
    "convert_pkcs10"  => {"DATA" => 1,
                          "IN"   => [ 'DER', 'PEM' ],
                          "OUT"  => [ 'DER', 'PEM', 'TXT']
                         },
    "create_pkcs10"   => {"PASSWD"  => 0,
                          "KEY"     => 0,
                          "SUBJECT" => 1},
    "create_pkcs12"   => {"PKCS12_PASSWD"  => 0,
                          "PASSWD"         => 1,
                          "NOPASSWD"       => ["__undef",0,1],
                          "CERT_PBE"        => ["__undef","PBE-MD2-DES","PBE-MD5-DES","PBE-SHA1-RC2-64","PBE-MD2-RC2-64","PBE-MD5-RC2-64","PBE-SHA1-DES","PBE-SHA1-RC4-128","PBE-SHA1-RC4-40","PBE-SHA1-3DES","PBE-SHA1-2DES","PBE-SHA1-RC2-128","PBE-SHA1-RC2-40"],
                          "KEY_PBE"        => ["__undef","PBE-MD2-DES","PBE-MD5-DES","PBE-SHA1-RC2-64","PBE-MD2-RC2-64","PBE-MD5-RC2-64","PBE-SHA1-DES","PBE-SHA1-RC4-128","PBE-SHA1-RC4-40","PBE-SHA1-3DES","PBE-SHA1-2DES","PBE-SHA1-RC2-128","PBE-SHA1-RC2-40"],
                          "KEY"            => 1,
                          "CERT"           => 1,
                          "CHAIN"          => 0,
                          "CSP"            => 0,
                          "ALIAS"          => 0,
                         },
    "create_random"   => {"RETURN_LENGTH" => 0,
                          "RANDOM_LENGTH" => 0,
                          "INCLUDE_PADDING" => 0},
    "get_pkcs8_keytype" => { 'DATA'   => 1,
                            'PASSWD' => 1,
                           },
    'is_issuer'       => {
                            'CERT'             => 1,
                            'POTENTIAL_ISSUER' => 1,
                         },
    "is_prime"        => {"PRIME"   => 1,
                         },
    "issue_cert"      => {"PROFILE" => 1,
                          "CSR"     => 1},
    "issue_crl"       => {"PROFILE" => 1,
                          "REVOKED" => 0,
                          "CERTLIST" => 0},
    "pkcs7_decrypt"   => {"PASSWD" => 0,
                          "KEY"    => 0,
                          "CERT"   => 0,
                          "PKCS7"  => 1},
    "pkcs7_encrypt"   => {"CERT"    => 0,
                          "OUTFORM"    => 0,
                          "ENC_ALG" => ["__undef", "aes256","aes192","aes128","idea","des3","des"],
                          "CONTENT" => 1},
    "pkcs7_get_chain" => {"NOCHAIN" => 0,
                          "NOSORT" => 0,
                          "PKCS7"  => 1},
    "pkcs7_sign"      => {"PASSWD"  => 0,
                          "KEY"     => 0,
                          "CERT"    => 0,
                          "CONTENT" => 1},
    "pkcs7_verify"    => {"CHAIN"   => 0, # optional only when NO_VERIFY is set
                          "NO_CHAIN" => 0,
                          "CONTENT" => 0,
                          "PKCS7"   => 1},
    "verify_cert"    =>  {"CHAIN"   => 0,
                          "CERTIFICATE" => 1,
                          "TRUSTED"   => 1,
                          "NOVALIDITY" => 0 },
    "create_pkey"    =>  {"PASSWD"   => 1,
                          "KEY_ALG" => 0, # default RSA
                          "ENC_ALG" => 0, # default aes256
                          "PKEYOPT" => 0,
                          "PARAM" => 0,
                          },
    "create_params"   =>  {"TYPE"   => 1, # DSA or DH
                          "PKEYOPT" => 1,
                          },
    "asn1_genconf"    => {"DATA" => 1 },

    };

    ## reassign the updated value to the command_params attribute
    $self->set_command_params($command_params);
   ##! 16: 'end'
}

sub START {
    ##! 16: 'start'
    my ($self, $ident, $arg_ref) = @_;

    ## check for missing but required parameters

    $self->__init_command_params();

    ##! 16: 'after __init_command_params()'
    ##! 16: 'get_command_params() child: ' . Dumper($self->get_command_params())
    ##FIXME - create useful checks
    if (0) {
        if (not exists $arg_ref->{NAME}) {
            OpenXPKI::Exception->throw (
                message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_NEW_MISSING_NAME");
        }

        if (not exists $arg_ref->{TOKEN_TYPE}) {
            OpenXPKI::Exception->throw (
                message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_NEW_MISSING_TOKEN_TYPE");
        }
    }

    delete $arg_ref->{CLASS};

    foreach my $key (keys %{$arg_ref})
    {
        next if (grep /^$key$/, ("TMP", "NAME",
                                 "TOKEN_TYPE",
                                 "CERTIFICATE", "SECRET"));
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_NEW_ILLEGAL_PARAMETER",
            params  => {NAME => $key, VALUE => $arg_ref->{$key}});
    }
}

sub get_cmd_param {
    my $self = shift;
    my $arg = shift;

    my $command_params = $self->get_command_params();
    my %rc = %{$command_params->{$arg}};
    ### %rc
    #return $command_params->{$arg};
    return \%rc;
}

sub get_object {
    my $self = shift;
    my $ident = ident $self;
    my $keys = shift;

    foreach my $param (keys %{$keys})
    {
        if ($param ne "DATA" and
            $param ne "FORMAT" and
            $param ne "TYPE")
        {
            OpenXPKI::Exception->throw (
                message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_ILLEGAL_PARAM",
                params  => {NAME => $param, VALUE => $keys->{$param}});
        }
    }

    if (not defined $keys->{DATA} or
        not length $keys->{DATA})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_MISSING_DATA");
    }

    if ($keys->{TYPE} ne "X509" and
        $keys->{TYPE} ne "CSR" and
        $keys->{TYPE} ne "CRL")
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_ILLEGAL_TYPE",
            params  => {TYPE => $keys->{TYPE}});
    }

    $keys->{FORMAT} = "PEM" if (not $keys->{FORMAT});
    $keys->{FORMAT} = "PEM" if ($keys->{TYPE} eq "CSR" and $keys->{FORMAT} eq "PKCS10");

    if ($keys->{FORMAT} ne "PEM" and
        $keys->{FORMAT} ne "DER" and
        ($keys->{TYPE} ne "CSR" or $keys->{FORMAT} ne "SPKAC")
       )
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_ILLEGAL_FORMAT",
            params  => {TYPE => $keys->{TYPE}, FORMAT => $keys->{FORMAT}});
    }

    my $ref = $self->get_instance()->get_object($keys);
    if ($keys->{TYPE} eq "CSR" and $keys->{FORMAT} eq "SPKAC")
    {
        $object_cache_of{$ident}->{$ref} = "SPKAC";
    } else {
        $object_cache_of{$ident}->{$ref} = $keys->{TYPE};
    }
    return $ref;
}

sub get_object_function {
    my $self = shift;
    my $ident = ident $self;
    my $keys = shift;

    foreach my $param (keys %{$keys})
    {
        if ($param ne "OBJECT" and
            $param ne "FUNCTION")
        {
            OpenXPKI::Exception->throw (
                message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_FUNCTION_ILLEGAL_PARAM",
                params  => {NAME => $param, VALUE => $keys->{$param}});
        }
    }

    if (not ref $keys->{OBJECT})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_FUNCTION_OBJECT_NO_REF");
    }

    if (not exists $object_cache_of{$ident} or
        not exists $object_cache_of{$ident}->{$keys->{OBJECT}})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_FUNCTION_OBJECT_NOT_IN_CACHE");
    }

    my $type = $object_cache_of{$ident}->{$keys->{OBJECT}};

    my @functions = ();
    if ($type eq "X509")
    {
        @functions = ("serial", "subject", "issuer", "notbefore", "notafter",
                      "alias", "modulus", "pubkey", "pubkey_hash", "fingerprint", "emailaddress",
                      "version", "pubkey_algorithm", "signature_algorithm", "exponent",
                      "keysize", "extensions", "openssl_subject"
                     );
    }
    elsif ($type eq "CSR")
    {
        @functions = ("subject", "version", "signature_algorithm",
                      "pubkey", "pubkey_hash", "keysize", "pubkey_algorithm",
                      "exponent", "modulus", "extensions","attributes");
    }
    elsif ($type eq "SPKAC")
    {
        @functions = ("pubkey", "keysize", "pubkey_algorithm", "exponent", "modulus",
                      "pubkey_hash", "signature_algorithm");
    }
    else ## CRL
    {
        @functions = ("version", "issuer", "next_update", "last_update",
                      "signature_algorithm", "revoked", "serial", "itemcnt", "extensions");
    }

    if (not grep (/$keys->{FUNCTION}/, @functions))
    {
         OpenXPKI::Exception->throw (
             message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_GET_OBJECT_FUNCTION_ILLEGAL_FUNCTION",
             params  => {FUNCTION => $keys->{FUNCTION}, TYPE => $type});
    }

    return $self->get_instance()->get_object_function($keys);
}

sub free_object {
    my $self   = shift;
    my $ident  = ident $self;
    my $object = shift;

    if (not ref $object)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_FREE_OBJECT_NO_REF");
    }

    if (not exists $object_cache_of{$ident} or
        not exists $object_cache_of{$ident}->{$object})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_BACKEND_API_FREE_OBJECT_NOT_IN_CACHE");
    }

    delete $object_cache_of{$ident}->{$object};
    return $self->get_instance()->free_object ($object);
}

sub key_usable {
    ##! 1: 'start'
    my $self  = shift;
    my $ident = ident $self;
    ##! 16: 'engine: ' . $self->get_instance()->get_engine()
    return if (!defined $self->get_instance()->get_engine());
    my $result;
    eval {
        # try to call key_usable, if this fails, key is unusable
        $result = $self->get_instance()->get_engine()->key_usable();
    };
    if ($EVAL_ERROR) {
        ##! 16: 'we have an eval error: ' . $EVAL_ERROR
        return;
    }
    ##! 16: 'result: ' . $result
    return $result;
}

1;
__END__

=head1 Name

OpenXPKI::Crypto::Backend::API - API for cryptographic backends.

=head1 Description

this is the basic class for crypto backend API. It inherits from
OpenXPKI::Crypto::API

=head1 Functions

=head2 START

is the constructor.

=head2 get_cmd_param

get the command_params entry for the specified command

