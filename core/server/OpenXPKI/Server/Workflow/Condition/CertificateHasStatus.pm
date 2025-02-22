# OpenXPKI::Server::Workflow::Condition::CertificateHasStatus
# Written by Oliver Welter for the OpenXPKI project 2012
# Copyright (c) 2012 by The OpenXPKI Project
package OpenXPKI::Server::Workflow::Condition::CertificateHasStatus;

use strict;
use warnings;
use base qw( OpenXPKI::Server::Workflow::Condition );
use Workflow::Exception qw( condition_error configuration_error );
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Serialization::Simple;
use OpenXPKI::Debug;
use English;
use OpenXPKI::Exception;


sub _evaluate {
    ##! 1: 'start'
    my ( $self, $workflow ) = @_;
    my $context     = $workflow->context();
    my $pki_realm   = CTX('session')->data->pki_realm;

    my $identifier = $self->param('cert_identifier') // $context->param('cert_identifier');

    OpenXPKI::Exception->throw(
        message => 'certificate has status identifier missing',
    ) unless $identifier;

    my $expected_status = $self->param('expected_status');
    ##! 16: "Expected status " . $expected_status
    if ($expected_status !~ /\A(ISSUED|REVOKED|CRL_ISSUANCE_PENDING)\z/) {
        configuration_error('certificate has status expected status missing or invalid');
    }

    my $cert = CTX('dbi')->select_one(
        from => 'certificate',
        columns => [ 'status' ],
        where => {
            identifier => $identifier,
            pki_realm  => $pki_realm,
        }
    );

    if (not $cert) {
        ##! 16: 'cert not found '
        CTX('log')->application()->debug("Cert status check failed, certificate not found " . $identifier);

        condition_error 'certificate has status cert not found';

    }

    ##! 16: 'status: ' . $cert->{'STATUS'}
    if ($cert->{status} ne $expected_status) {
        CTX('log')->application()->debug("Cert status check failed: ".$cert->{status}. " != ".$expected_status);

        condition_error 'certificate has status does not match';
    }

    return 1;
}

1;

__END__

=head1 NAME

OpenXPKI::Server::Workflow::Condition::CertificateHasStatus

=head1 DESCRIPTION

The condition checks if the certificate identified by cert_identifier
has the status given in the parameter expected_status. Only certs in the
current realm are checked, if the certificate is not found, the condition
behaves as the status does not match but sends another verbose error.


=head1 Configuration

    is_certificate_issued:
        class: OpenXPKI::Server::Workflow::Condition::CertificateHasStatus
        param:
          expected_status: ISSUED

=head2 Parameters

=over

=item expected_status

The status to check against, expects a single status word, possible values
are ISSUED, REVOKED, CRL_ISSUANCE_PENDING

=item cert_identifier

The certificate to check, if not present as explicit parameter the context
value with same key will be used.

=back

