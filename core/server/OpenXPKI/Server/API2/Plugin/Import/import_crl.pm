package OpenXPKI::Server::API2::Plugin::Import::import_crl;
use OpenXPKI::Server::API2::EasyPlugin;

=head1 NAME

OpenXPKI::Server::API2::Plugin::Import::import_crl

=cut

# Project modules
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Server::API2::Types;
use OpenXPKI::Crypto::CRL;


=head1 COMMANDS

=head2 import_crl

Import a CRL into the current realm. This should be used only within realms that
work as a proxy to external CA systems or use external CRL
signer tokens.

The issuer is extracted from the CRL. Note that the issuer must be defined as
alias in the C<certsign> group.

A check for duplicate CRLs is done based on C<issuer>, C<last_update> and
C<next_update> fields.

The content of the CRL is NOT parsed, therefore the certificate status of
revoked certificates is NOT changed in the database!

Returns a I<HashRef> with the CRL informations inserted into the database, e.g.:

    {
        crl_key => '6655',
        issuer_identifier => 'RE35XR3XIBXiIbAu8P5aGMCmH7o',
        last_update => 1521556123,
        next_update => 3098356123,
        pki_realm => 'ca-one',
        publication_date => 0,
        items =>  42,
        crl_number  => 1234567,
    }

B<Parameters>

=over

=item * C<data> I<Str> - PEM formated CRL. Required.

=back

B<Changes compared to API v1:>

The previously unused parameter C<ISSUER> was removed.

=cut
command "import_crl" => {
    data   => { isa => 'PEM', required => 1, },
} => sub {
    my ($self, $params) = @_;

    my $pki_realm = CTX('session')->data->pki_realm;
    my $dbi = CTX('dbi');

    my $crl_obj = OpenXPKI::Crypto::CRL->new(
        TOKEN => $self->api->get_default_token,
        DATA  => $params->data,
        EXTENSIONS => 1,
    );

    # Find the issuer certificate
    my $issuer_aik = $crl_obj->{PARSED}->{BODY}->{EXTENSIONS}->{AUTHORITY_KEY_IDENTIFIER};
    my $issuer_dn = $crl_obj->{PARSED}->{BODY}->{ISSUER};

    # We need the group name for the alias group
    my $group = CTX('config')->get(['crypto', 'type', 'certsign']);

    ##! 16: 'Look for issuer ' . $issuer_aik . '/' . $issuer_dn . ' in group ' . $group

    my $where = {
        'aliases.pki_realm' => $pki_realm,
        'aliases.group_id' => $group,
        $issuer_aik
            ? ('certificate.subject_key_identifier' => $issuer_aik)
            : ('certificate.subject' => $issuer_dn),
    };

    my $issuer = $dbi->select_one(
        from_join => 'certificate  identifier=identifier aliases',
        columns => [ 'certificate.identifier' ],
        where => $where
    ) or OpenXPKI::Exception->throw(
        message => 'I18N_OPENXPKI_UI_IMPORT_CRL_ISSUER_NOT_FOUND',
        params => { issuer_dn => $issuer_dn , group => $group, issuer_aik => $issuer_aik },
    );

    ##! 32: 'Issuer ' . Dumper $issuer

    my $serial = $dbi->next_id('crl');
    my $ca_identifier = $issuer->{identifier};


    my %data_crl_obj = $crl_obj->to_db_hash(); # keys: DATA, LAST_UPDATE, NEXT_UPDATE
    my $data = {
        # FIXME #legacydb Change upper to lower case in OpenXPKI::Crypto::CRL->to_db_hash(), not here
        ( map { lc($_) => $data_crl_obj{$_} } keys %data_crl_obj ),
        pki_realm         => $pki_realm,
        issuer_identifier => $ca_identifier,
        crl_key           => $serial,
        publication_date  => 0,
        items             =>  $crl_obj->{PARSED}->{BODY}->{ITEMCNT},
        crl_number        =>  $crl_obj->{PARSED}->{BODY}->{SERIAL},
    };

    my $duplicate = $dbi->select_one(
        from => 'crl',
        columns => [ 'crl_key' ],
        where => {
            'pki_realm' => $pki_realm,
            'issuer_identifier' => $ca_identifier,
            'last_update' => $data->{last_update},
            'next_update' => $data->{next_update},
        },
    );

    if ($duplicate) {
        OpenXPKI::Exception->throw(
            message => 'I18N_OPENXPKI_UI_IMPORT_CRL_DUPLICATE',
            params => {
                'issuer_identifier' => $ca_identifier,
                'last_update' => $data->{last_update},
                'next_update' => $data->{next_update},
                'crl_key' => $duplicate->{crl_key},
            },
        );
    }

    ##! 32: 'CRL Data ' . Dumper $data

    $dbi->insert( into => 'crl', values => $data );
    CTX('log')->application()->info("Imported CRL for issuer $issuer_dn");

    delete $data->{data};
    return $data;
};

__PACKAGE__->meta->make_immutable;
