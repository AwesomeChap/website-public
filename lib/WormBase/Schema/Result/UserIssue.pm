package WormBase::Schema::Result::UserIssue;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 NAME

WormBase::Schema::Result::UserIssue

=cut

__PACKAGE__->table("users_to_issues");



__PACKAGE__->add_columns(
  "user_id",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "issue_id",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
);
__PACKAGE__->set_primary_key("user_id", "issue_id");


# Created by DBIx::Class::Schema::Loader v0.07001 @ 2010-08-20 14:27:11
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aWUX+zL4WtBgQQBgwyvCyg

__PACKAGE__->belongs_to(user=>'WormBase::Schema::Result::User','user_id');
__PACKAGE__->belongs_to(issue=>'WormBase::Schema::Result::Issue','issue_id');
# You can replace this text with custom content, and it will be preserved on regeneration
1;
