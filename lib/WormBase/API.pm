package WormBase::API;

use Moose;                       # Moosey goodness

use WormBase::API::ModelMap;
use WormBase::API::Service::Xapian;
use Search::Xapian qw/:all/;
use Config::General;
use Class::MOP;
use File::Spec;
use namespace::autoclean -except => 'meta';

with 'WormBase::API::Role::Logger'; # A basic Log::Log4perl screen appender

# We assume that there is a single default data source.
# For now this is AceDB.
has 'default_datasource' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'acedb',
);

# Dynamically establish a list of available data services.
# This includes the default_datasource and other singletons.
has '_services' => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

has 'stringified_responses' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 1,
);

# This is just the configuration directory
# for instantiating Log::Log4perl object. Janky.
has pre_compile => (
    is       => 'rw',
);

has conf_dir => (
    is       => 'ro',
    required => 1,
);
# This is the configuration object/hashref for databases info e.g. connection hosts password...
has database => (
    is       => 'ro',
    required => 1,
    #    lazy_build => 1,
);

has tmp_base => (
    is       => 'rw',
);

has xapian => (
    is     => 'rw',
    isa    => 'WormBase::API::Service::Xapian',
    lazy_build      => 1,
);

# this is for the view (see /template/config/main)
# it's a nasty hack. it simply reveals WormBase::API::ModelMap to the view
# so that the maps can be accessed from there. this is heavily coupled
# with the internals of ModelMap.
has modelmap => (
    is => 'ro',
    lazy => 1,
    required => 1,
    default => sub {
        return WormBase::API::ModelMap->new; # just a blessed scalar ref
    },
);

has _tools => (
    is       => 'ro',
    lazy_build      => 1,
);

has tool => (
    is       => 'rw',
);

# builds a search object with the default datasource
sub _build_xapian {
  my $self = shift;

  my $service_instance = $self->_services->{$self->default_datasource};

  my $path = File::Spec->catdir($self->pre_compile->{base}, $self->version, 'search');
  my $db = Search::Xapian::Database->new(File::Spec->catfile($path, 'main'));
  my $syn_db = Search::Xapian::Database->new(File::Spec->catfile($path, 'syn'));
  my $qp = Search::Xapian::QueryParser->new($db);
  my $auto_qp = Search::Xapian::QueryParser->new($db);
  my $syn_qp = Search::Xapian::QueryParser->new($syn_db);
  $qp->set_default_op(OP_OR);

  my $ptype_svrp = Search::Xapian::NumberValueRangeProcessor->new(8, "ptype:");
  my $type_svrp = Search::Xapian::StringValueRangeProcessor->new(2);
  my $species_svrp = Search::Xapian::NumberValueRangeProcessor->new(3, "species:");
  $qp->add_valuerangeprocessor($ptype_svrp);
  $qp->add_valuerangeprocessor($species_svrp);
  $qp->add_valuerangeprocessor($type_svrp);



  my $svrp = Search::Xapian::StringValueRangeProcessor->new(2);
  $syn_qp->add_valuerangeprocessor($svrp);

  my $xapian = WormBase::API::Service::Xapian->new({db => $db, qp => $qp, syn_db => $syn_db, syn_qp => $syn_qp});

  $xapian->search($self, "*", 1, "gene");
  $xapian->search_autocomplete($self, "*", "gene");

  return $xapian;
}

# Version should be provided by the default datasource or set explicitly.
sub version {
    my $self = shift;
    # Fetch the dbh for the default datasource
    my $service = $self->_services->{$self->default_datasource};
    return $service->version;
}

# Build a hashref of services, including things like the
# default datasource, GFF databases, etc.
sub _build__services {
    my ($self) = @_;

    my %services;

    my $db_confs = $self->database;
    foreach my $db_type (sort keys %$db_confs) {
        next if $db_type eq 'tmp';
        my $service_class = __PACKAGE__ . "::Service::$db_type";
        Class::MOP::load_class($service_class);

        my $conf = $db_confs->{$db_type};
        my @sources = sort keys %{$conf->{data_sources}}; # usually species
        # some of the DBs may not have specific data sources but
        # we'd still like to set them up below
        @sources = '' unless @sources;

        foreach my $source (@sources) {
            my $service = $service_class->new({
                conf          => $conf,
                log           => $self->log,
                source        => $source,
                symbolic_name => $db_type,
                tmp_base      => $db_confs->{tmp},
            });

            my $full_name = $source ? "${db_type}_${source}" : $db_type;
            $services{$full_name} = $service;
            $self->log->debug("service $full_name registered but not yet connected");
        }
    }

    return \%services;
}

sub _build__tools {
    my ($self) = @_;
    my %tools;
    for my $tool (sort keys %{$self->tool}) {
        my $class = __PACKAGE__ . "::Service::$tool";
        Class::MOP::load_class($class);

        # Instantiate the service providing it with
        # access to some of our configuration variables
        $tools{$tool}  = $class->new({
            pre_compile => $self->tool->{$tool},
            log         => $self->log,
	    search 	=> $self->xapian,
            dsn         => $self->_services, 
            tmp_base    => $self->tmp_base,
            # ($tool eq 'aligner' ? (search => $self->search) : ()),
        });
        $self->log->debug( "service $tool registered");
    }
    return \%tools;
}

# Fetches a WormBase object corresponding to an Ace object
# or the Ace object itself if nowrap is specified.
# TODO: Standardize return values. Currently returns object if fetched,
#       0 if can't get DB handle, and -1 if can't seem to fetch object.
#       Consider throwing an exception and return;, respectively. Will
#       Require modifying places where $api->fetch is called.
sub fetch {
    my ($self,$args) = @_;

    my ($object, $class, $aceclass, $name, $nowrap)
        = @{$args}{qw(object class aceclass name nowrap)};

    if ($object) {
        $class = $self->modelmap->ACE2WB_MAP->{fullclass}->{$object->class};
        $self->log->debug("[API::fetch()]", " object $object, inferred WB class $class");
    }
    else {
        my $service_dbh = $self->_services->{$self->default_datasource}->dbh || return 0;

        # resolve classes to properly retrieve object
        if ($class) { # WB class was provided
            $aceclass = $self->modelmap->WB2ACE_MAP->{class}->{$class}
                     || $self->modelmap->WB2ACE_MAP->{fullclass}->{$class};

            unless ($aceclass) { # don't know which aceclass;
                $self->log->warn("[API::fetch()]", " class $class, UNKNOWN ace class");
                return 0;
            }
        }
        else { # aceclass provided (assumption), WB class not
            $class = $self->modelmap->ACE2WB_MAP->{fullclass}->{$aceclass};

            unless ($class) { # an aceclass we don't handle [yet]?
                $self->log->warn("[API::fetch()]", " ace class $aceclass, UNKNOWN WB class");
                return 0;
            }
        }

        # HACK for variation -- resolve variation name first
        if ($aceclass eq 'Variation' and $name !~ /^WBVar/ and
            my $var_name = $service_dbh->fetch(-class => 'Variation_name', -name => $name)) {
            my $orig_name = $name; # for debug
            $name = $var_name->Public_name_for || $var_name->Other_name_for || $name;
            $self->log->debug("[API::fetch()]", " Variation hack, $orig_name, found $name");
        }
 
        # Try fetching an object (from the default data source)
		if (ref $aceclass eq 'ARRAY') { # multiple Ace classes
			foreach my $ace (@$aceclass) {
				$self->log->debug("[API::fetch()]",
                                  " attempt to fetch $name of ace class $ace");
				last if $object = $service_dbh->fetch(-class => $ace, -name => $name);
			}
		}elsif ($aceclass eq 'Disease' ) {
		     $self->log->debug("[API::fetch()]",
                                  " attempt to fetch $name of ace class $aceclass");
 		     $object = $self->xapian->_get_tag_info($self, $name, lc($aceclass),1);       
		}
		else { # assume a single Ace class
		    $self->log->debug("[API::fetch()]",
                              " attempt to fetch $name of ace class $aceclass");
			$object = $service_dbh->fetch(-class => $aceclass, -name => $name);
		}
    }

    unless (defined $object) { #&& ($name eq 'all' || $name eq '*'));
        $self->log->warn("[API::fetch()]", " could NOT fetch object");
        return -1;
    }

    return $object if $nowrap;
    return $self->instantiate_object($class => $object);
}

# Instantiate but without fetching an ace object
sub instantiate_empty {
    my ($self,$class) = @_;
    unless ($class) {
        $self->log->error('[API::instantiate_empty]',
                          ' Tried to instantiate an empty object without a class');
        return;
    }
    return $self->instantiate_object($class);
}

sub wrap {
    my $self = shift;
    my @wrapped = map { $self->instantiate_object($_) } @_;

    # User might have passed and expected just a single object
    return wantarray ? @wrapped : $wrapped[0];
}

{
    my $PREFIX = __PACKAGE__ . '::Object::';
    my $PACKRE = qr/^$PREFIX/;

    # $self->instantiate_object($object); will infer from $object->class and ModelMap
    # $self->instantiate_object($class => $object);
    sub instantiate_object {
        my ($self, $class, $object) = @_;
        if (ref $class) {       # instantiate_object($obj) form
            $object = $class;
            $class  = $self->modelmap->ACE2WB_MAP->{fullclass}{$object->class};
        }

        if (!defined $class) {
            $self->log->error('[API::instantiate_object]',
                              " Tried to instantiate a WB object without a corresponding WB class");
            return;
        }

        $class = $PREFIX . $class unless $class =~ $PACKRE;

        return $class->new(
            object      => $object,
            log         => $self->log,
            dsn         => $self->_services,
            tmp_base    => $self->tmp_base,
            pre_compile => $self->pre_compile,
            _api        => $self,
        );
    }

}

1;

