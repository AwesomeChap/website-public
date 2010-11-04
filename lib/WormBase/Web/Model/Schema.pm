package WormBase::Web::Model::Schema;

use strict;
use base 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    schema_class => 'WormBase::Schema',
    
    connect_info => {
        dsn => 'dbi:mysql:wormbase_user',
        user => 'wb',
        password => '',
    }
);

=head1 NAME

WormBase::Web::Model::Schema - Catalyst DBIC Schema Model

=head1 SYNOPSIS

See L<WormBase::Web>

=head1 DESCRIPTION

L<Catalyst::Model::DBIC::Schema> Model using schema L<WormBase::Schema>

=head1 GENERATED BY

Catalyst::Helper::Model::DBIC::Schema - 0.25

=head1 AUTHOR

A clever guy

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
