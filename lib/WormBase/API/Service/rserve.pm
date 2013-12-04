package WormBase::API::Service::rserve;

use File::Basename;
use File::Copy;
use IPC::Run3;
use Data::UUID;

use Moose;
with 'WormBase::API::Role::Object';

sub init_chart {
    my ($self, $filename, $data, $format) = @_;

    # Setup output file:
    my $image_tmp_path = undef;
    if (defined $filename) {
        $image_tmp_path = "/tmp/" . $filename;
    } else  {
        my $uuid_generator = new Data::UUID;
        my $image_basename = $uuid_generator->create_str();
        $image_tmp_path = "/tmp/" . $image_basename . "." . $format;
    }
    my $image_filename = basename($image_tmp_path);

    my @labels = ();
    my @values = ();
    my @projects = ();
    my @life_stages = ();
    foreach my $datum (@$data) {
        push(@labels, '"' . $datum->{label} . '"');
        push(@values, $datum->{value});
        push(@projects, '"' . $datum->{project} . '"');
        push(@life_stages, '"' . $datum->{life_stage} . '"');
    }
    my $label_list = join(",\n", @labels);
    my $value_list = join(",\n", @values);
    my $project_list = join(",\n", @projects);
    my $life_stage_list = join(",\n", @life_stages);

    return ($image_tmp_path, $image_filename, $label_list, $value_list, $project_list, $life_stage_list);
}

sub execute_r_program {
    my ($self, $r_program, $image_tmp_path, $image_filename) = @_;

    run3([ 'ruby', 'script/rserve_client.rb' ], \$r_program);

    # Relocate the plot into an accessible directory of the web-server:
    my $destination = WormBase::Web->config->{rplots} . $image_filename;
    # TODO: figure out why `move($image_tmp_path, $destination);` does not work anymore!
    system('mv', $image_tmp_path, $destination);

    # Return the absolute URI (relative to the server) of the generated image:
print STDOUT "--> $image_filename\n";
    return {
        uri => WormBase::Web->config->{rplots_url_suffix} . $image_filename
    };
}

# Take customization parameters and return values that can be used in an R command:
sub barboxchart_parameters {
    my ($self, $customization) = @_;

    my $height = $customization->{height};
    if ($customization->{adjust_height_for_less_than_X_facets}) {
        my $normally_assumed_facets = $customization->{adjust_height_for_less_than_X_facets};
        $height = "$height / ($normally_assumed_facets - length(levels(factor(projects))) + 1)";
    }

    # Pretty-ization:
    return ($customization->{filename},
            $customization->{xlabel},
            $customization->{ylabel},
            $customization->{width},
            $height,
            $customization->{rotate} ? " + coord_flip()" : "",
            $customization->{bw} ? "scale_fill_manual(values = rep(\"white\", length(projects))" : "scale_fill_brewer(palette = \"Dark2\"",
            $customization->{facets} ? ", guide = FALSE" : "",
            $customization->{facets} ? " + facet_grid(projects ~ .)" : "");
}

# Plots a barchart with the given values and labels. This implementation
# is currently tailored to work with data that also provides information
# about project and life stage association.
#
# Format example:
#
#  [
#    {
#      'value'      => '3.97874',
#      'label'      => 'RNASeq_Hillier.L4_larva_Male_cap2_Replicate2',
#      'project'    => 'RNASeq_Hillier',
#      'life_stage' => 'WBls:0000024'
#    },
#    {
#      'value'      => '1e-10',
#      'label'      => 'RNASeq.elegans.SRP015688.L4.linker-cells.nhr-67.4',
#      'project'    => 'RNASeq_Hillier',
#      'life_stage' => 'WBls:0000024'
#    },
#    {
#      'value'      => '5.7759',
#      'label'      => 'RNASeq_Hillier.L4_Larva_Replicate1',
#      'project'    => 'RNASeq_Hillier',
#      'life_stage' => 'WBls:0000024'
#    },
#    ...
sub barchart {
    my ($self, $data, $customization) = @_;

    # Pretty-ization:
    my ($filename, $xlabel, $ylabel, $width, $height, $rotate, $coloring, $facets_guides, $facets_grid) = $self->barboxchart_parameters($customization);

    # If a filename is provided and the plot exists already: do not generate it again!
    return { uri => "/img-static/rplots/" . $filename } if (WormBase::Web->config->{installation_type} ne 'development' && defined $filename && -e (WormBase::Web->config->{rplots} . $filename));

    my $format = "png";
    my ($image_tmp_path, $image_filename, $label_list, $value_list, $project_list, $life_stage_list) = $self->init_chart($filename, $data, $format);

    # Run the R program that plots the barchart:
    my $r_program = <<EOP
library("Defaults");
setDefaults(q, save="no");
useDefaults(q);

library("ggplot2");
labels = c($label_list);
values = c($value_list);
projects = c($project_list);
life_stages = c($life_stage_list);
data = data.frame(labels, values, projects, life_stages);

# Preserve ordering:
data\$labels = factor(labels, levels = labels, ordered = TRUE)

$format("$image_tmp_path", width = $width, height = $height);
print(ggplot(data, aes(x = labels, y = values, fill = projects)) + geom_bar(stat="identity")$rotate + labs(x = "$xlabel", y = "$ylabel") + theme(text = element_text(size = 21), axis.text = element_text(colour = 'black')) + $coloring$facets_guides)$facets_grid);
dev.off();
EOP
;

    # Return the absolute URI (relative to the server) of the generated image:
    return $self->execute_r_program($r_program, $image_tmp_path, $image_filename);
}

# Plots a boxplot with the given values and labels. This implementation
# is currently tailored to work with data that also provides information
# about project and life stage association.
#
# Format example:
#
#  [
#    {
#      'value'      => '3.97874',
#      'label'      => 'RNASeq_Hillier.L4_larva_Male_cap2_Replicate2',
#      'project'    => 'RNASeq_Hillier',
#      'life_stage' => 'WBls:0000024'
#    },
#    {
#      'value'      => '1e-10',
#      'label'      => 'RNASeq.elegans.SRP015688.L4.linker-cells.nhr-67.4',
#      'project'    => 'RNASeq_Hillier',
#      'life_stage' => 'WBls:0000024'
#    },
#    {
#      'value'      => '5.7759',
#      'label'      => 'RNASeq_Hillier.L4_Larva_Replicate1',
#      'project'    => 'RNASeq_Hillier',
#      'life_stage' => 'WBls:0000024'
#    },
#    ...
sub boxplot {
    my ($self, $data, $customization) = @_;

    # Pretty-ization:
    my ($filename, $xlabel, $ylabel, $width, $height, $rotate, $coloring, $facets_guides, $facets_grid) = $self->barboxchart_parameters($customization);

    # If a filename is provided and the plot exists already: do not generate it again!
    return { uri => "/img-static/rplots/" . $filename } if (WormBase::Web->config->{installation_type} ne 'development' && defined $filename && -e (WormBase::Web->config->{rplots} . $filename));

    my $format = "png";
    my ($image_tmp_path, $image_filename, $label_list, $value_list, $project_list, $life_stage_list) = $self->init_chart($filename, $data, $format);

    # Run the R program that plots the barchart:
    my $r_program = <<EOP
library("Defaults");
setDefaults(q, save="no");
useDefaults(q);

library("ggplot2");
labels = c($label_list);
values = c($value_list);
projects = c($project_list);
life_stages = c($life_stage_list);
data = data.frame(labels, values, projects, life_stages);

# Preserve ordering:
data\$life_stages = factor(life_stages, levels = life_stages, ordered = TRUE)

$format("$image_tmp_path", width = $width, height = $height);
print(ggplot(data, aes(factor(life_stages), y = values, fill = projects)) + geom_boxplot()$rotate + labs(x = "$xlabel", y = "$ylabel") + theme(text = element_text(size = 21), axis.text = element_text(colour = 'black')) + $coloring$facets_guides)$facets_grid);
dev.off();
EOP
;

    # Return the absolute URI (relative to the server) of the generated image:
    return $self->execute_r_program($r_program, $image_tmp_path, $image_filename);
}

1;

