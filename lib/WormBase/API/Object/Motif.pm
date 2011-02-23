package WormBase::API::Object::Motif;
use Moose;

with 'WormBase::API::Role::Object';
extends 'WormBase::API::Object';

=pod 

=head1 NAME

WormBase::API::Object::Motif

=head1 SYNPOSIS

Model for the Ace ?Motif class.

=head1 URL

http://wormbase.org/species/motif

=head1 TODO

=cut

###################
## Identification
###################

=head2 title

This method will return a data structure of the 
title for the requested motif.

=head3 PERL API

 $data = $model->title();

=head3 REST API

=head4 Request Method

GET

=head4 Requires Authentication

No

=head4 Parameters

a Motif ID ((AAATG)n)

=head4 Returns

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

=head4 Request example

curl -H content-type:application/json http://api.wormbase.org/rest/field/motif/(AAATG)n/title

=head4 Response example

<div class="response-example"></div>

=cut 

sub title {
	my $self 	= shift;
	my $object 	= $self->object;
	my $data_pack = $object->Title;

	my $data = {
				'data'=> $data_pack,
				'description' => 'title for the motif'
				};
	return $data;
}

=head2 remarks

This method will return a data structure with
remarks re: the requested motif.

=head3 PERL API

 $data = $model->remarks();

=head3 REST API

=head4 Request Method

GET

=head4 Requires Authentication

No

=head4 Parameters

a Motif ID ((AAATG)n)

=head4 Returns

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

=head4 Request example

curl -H content-type:application/json http://api.wormbase.org/rest/field/motif/(AAATG)n/remarks

=head4 Response example

<div class="response-example"></div>

=cut 


sub remarks {
	my $self 	= shift;
    my $object 	= $self->object;
	my $data_pack = $object->Remark;

	my $data = {
				'data'=> $data_pack,
				'description' => 'remarks regarding motif'
				};
	return $data;	
}


=head2 database

This method will return a data structure with database information for the requested motif.

=head3 PERL API

 $data = $model->database();

=head3 REST API

=head4 Request Method

GET

=head4 Requires Authentication

No

=head4 Parameters

a Motif ID ((AAATG)n)

=head4 Returns

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

=head4 Request example

curl -H content-type:application/json http://api.wormbase.org/rest/field/motif/(AAATG)n/database

=head4 Response example

<div class="response-example"></div>

=cut 

sub database  {
	my $self = shift;
    my $object = $self->object;
	my ($database,$accession1,$accession2) = $object->Database('@')->row;
	my $accession = $accession2 || $accession1;
	
	my $data_pack = {'database' 	=> "$database",
					'accession' => "$accession"
	             };

	my $data = {
				'data'=> $data_pack,
				'description' => 'database which contained info on motif, along with its accession number'
				};
	return $data;
}

####################
## homology
####################

=head2 go

This method will return a data structure with go annotations for the requested motif.

=head3 PERL API

 $data = $model->go();

=head3 REST API

=head4 Request Method

GET

=head4 Requires Authentication

No

=head4 Parameters

a Motif ID ((AAATG)n)

=head4 Returns

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

=head4 Request example

curl -H content-type:application/json http://api.wormbase.org/rest/field/motif/(AAATG)n/go

=head4 Response example

<div class="response-example"></div>

=cut 

sub homologies {
	my $self = shift;
    my $object = $self->object;
	my @data_pack;
	
    foreach (qw/DNA_homol Pep_homol Motif_homol Homol_homol/) {
		if (my @homol = $motif->$_) {
			foreach (@homol) {
				my $id;
				my $label;
				my $class;
				my $homolog_data;
				if ($_ =~ /.*RepeatMasker/g) {
					$_ =~ /(.*):.*/;
					my $clone = $1;
					
					$homolog_data = {	
						'id'	=> "$clone",
						'label'	=> "$clone",
						'class' => 'Clone'
					};
				} else
					$homolog_data = $self->_pack_obj($_);	
				}
				push @data_pack, $homolog_data;
			}
		}       
	my $data = {
				'data'=> \@data_pack,
				'description' => 'homology data for this motif'
				};
	return $data;	
}

###################
## gene ontology
###################

=head2 homologies

This method will return a data structure with homology information on the requested motif.

=head3 PERL API

 $data = $model->homologies();

=head3 REST API

=head4 Request Method

GET

=head4 Requires Authentication

No

=head4 Parameters

a Motif ID ((AAATG)n)

=head4 Returns

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

=head4 Request example

curl -H content-type:application/json http://api.wormbase.org/rest/field/motif/(AAATG)n/homologies

=head4 Response example

<div class="response-example"></div>

=cut 

sub go  {
	my $self = shift;
    my $motif = $self->object;
	my @go_terms;
	@go_terms = $motif->GO_term;
	
	foreach my $go_term (@go_terms) {	
		my $definition = $go_term->Definition;
		my ($evidence) = $go_term->right;
		my $term = $go_term->GO_term;
		my $go_data;

		$go_data = (		
					'term_data' => {
						'id'=> "$go_term",
						'label' => "$term",
						'class'=>'GO_term'
					},	
				'definition'=>$definition,
				'evidence'=>$evidence
				);
				
		push @data_pack, $go_data;		

	my $data = {
				'data'=> \@data_pack,
				'description' => 'go terms to with which motif is annotated'
				};
	return $data;	
}

1;

