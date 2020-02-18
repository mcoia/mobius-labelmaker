#!/usr/bin/perl

package sierraCluster;


use Try::Tiny;
use Data::Dumper;


# for later
# Query to get branch codes translated to ID's
# select svb.code_num,svl.code,svbn.name,svbn.branch_id 
# -- select svbn.name,count(*)
# from
# -- select * from
# sierra_view.location svl,
# sierra_view.branch svb,
# sierra_view.branch_name svbn
# where
# svbn.branch_id=svb.id and
# svb.code_num=svl.branch_code_num

# limit 100


our $log;
our $driver;
our $screenshotDIR;

sub new
{
    my $class = shift;
    my $self = 
    {
        name => shift,
        dbHandler => shift,
        prefix => shift,
        webURL => '',
        webLogin => '',
        webPass => '',
        pgURL => '',
        pgPort => '',
        pgDB => '',
        pgUser => '',
        pgPass => '',
        clusterID => -1,
        error => 0
    };
    $driver = shift;
    $screenshotDIR = shift;
    $log = shift;
    if($self->{name} && $self->{dbHandler} && $self->{prefix} && $driver && $log)
    {
        getClusterVars($self) 
    }
    else
    {
        $self->{error} = 1;
    }
    bless $self, $class;
    return $self;
}



sub getClusterVars
{
    my ($self) = @_[0];

    my $query = "select 
    id,
    report_base_url,
    report_username,
    report_pass,
    postgres_url,
    postgres_db,
    postgres_port,
    postgres_username,
    postgres_password
    from
    ".$self->{prefix}.
    "_cluster
    where
    name = '".$self->{name}."'";

    my @results = @{$self->{dbHandler}->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $log->addLine("Cluster vals: ".Dumper(\@row));
        $self->{clusterID} = @row[0];
        $self->{webURL} = @row[1];
        $self->{webLogin} = @row[2];
        $self->{webPass} = @row[3];
        $self->{pgURL} = @row[4];
        $self->{pgDB} = @row[5];
        $self->{pgPort} = @row[6];
        $self->{pgUser} = @row[7];
        $self->{pgPass} = @row[8];
    }

    $self->{error} = 1 if($#results == -1);
}


sub scrape
{
    my ($self) = shift;
    my $monthsBack = shift || 5;
    my @dateScrapes = @{figureWhichDates($self)};

    
    if(!$self->{error})
    {
        $log->addLine("Getting " . $self->{webURL});
        $driver->get($self->{webURL});
        sleep 3; # initial page load takes time.
        takeScreenShot($self,'pageload');
        my $continue = handleLandingPage($self);
        $continue = handleLoginPage($self) if $continue;
        $continue = handleCircStatOwningHome($self) if $continue;
        foreach(@dateScrapes)
        {
            $continue = handleReportSelection($self,$_) if $continue;
            collectReportData($self) if $continue;
            exit;
        }
    }
   
}


sub collectReportData
{
    my ($self) = @_[0];
print "collectReportData\n";
    my @frameSearchElements = ('HOME LIBRARY TOTAL CIRCULATION');
        
    if(!switchToFrame($self,\@frameSearchElements))
    {
        my @table = $driver->find_elements('//table');
        
        
        $driver->switch_to_frame();
        
        
    }
    else
    {
        return 0;
    }
}
sub handleReportSelection
{
    my ($self) = @_[0];
    my $selection = @_[1];
print "handleReportSelection\n";
    my @frameSearchElements = ('TOTAL circulation', 'Choose a STARTING and ENDING month');
        
    if(!switchToFrame($self,\@frameSearchElements))
    {   
        my $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('td');
            var stop = 0;
            for(var i=0;i<doms.length;i++)
            {
                if(!stop)
                {
                    var thisaction = doms[i].innerHTML;

                    if(thisaction.match(/".$selection."/gi))
                    {
                        doms[i].getElementsByTagName('input')[0].click();
                        stop = 1;
                    }
                }
            }
            if(!stop)
            {
                return 'didnt find the button';
            }

            ");
        sleep 1;
        $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('form');
            for(var i=0;i<doms.length;i++)
            {
                doms[i].submit();
            }
        ");
        sleep 1;
        $driver->switch_to_frame();
        my $finished = handleReportSelection_processing_waiting($self);
        takeScreenShot($self,'handleReportSelection');
        return $finished;
    }
    else
    {
        return 0;
    }
}

sub handleReportSelection_processing_waiting
{
    my ($self) = @_[0];
    my $count = @_[1] || 0 ;
print "handleReportSelection_processing_waiting\n";
    my @frameSearchElements = ('This statistical report is calculating.');
        
    if(!switchToFrame($self,\@frameSearchElements)) ## will only exist while server is processing the request
    {
        if($count < 10) # only going to try this 10 times
        {
            my $owning = $driver->execute_script("
                var doms = document.getElementsByTagName('form');
                for(var i=0;i<doms.length;i++)
                {
                    doms[i].submit();
                }
            ");
            sleep 1;
            $driver->switch_to_frame();
            $count++;
            my $worked = handleReportSelection_processing_waiting($self,$count);
            return $worked;
        }
        else
        {
            return 0;
        }
    }
    else
    {
        return 1;
    }
}


sub handleLandingPage
{
    my ($self) = @_[0];
    print "handleLandingPage\n";
    my @frameSearchElements = ('Circ Activity', '<b>CIRCULATION<\/b>');
        
    if(!switchToFrame($self,\@frameSearchElements))
    {
        my @forms = $driver->find_elements('//form');
        foreach(@forms)
        {
            $thisForm = $_;
            if($thisForm->get_attribute("action") =~ /\/managerep\/startviews\/0\/d\/table_1x1/g )
            {
                $thisForm->submit();
            }
        }
        
        sleep 1;
        $driver->switch_to_frame();
        takeScreenShot($self,'handleLandingPage');
        return 1;
    }
    else
    {
        return 0;
    }
}

sub handleCircStatOwningHome
{
    my ($self) = @_[0];
print "handleCircStatOwningHome\n";
    my @frameSearchElements = ('Owning\/Home', 'htcircrep\/owning\/\/o\|\|\|\|\|\/');
    if(!switchToFrame($self,\@frameSearchElements))
    {   
        my $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('a');
            var stop = 0;
            for(var i=0;i<doms.length;i++)
            {
                if(!stop)
                {
                    var thisaction = doms[i].getAttribute('onClick');

                    if(thisaction.match(/htcircrep\\/owning\\/\\/o\\|\\|\\|\\|\\|\\//g))
                    {
                        doms[i].click();
                        stop = 1;
                    }
                }
            }
            if(!stop)
            {
                return 'didnt find the button';
            }

            ");
        sleep 1;
        $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('form');
            for(var i=0;i<doms.length;i++)
            {
                doms[i].submit();
            }
        ");
        sleep 1;
        $driver->switch_to_frame();
        takeScreenShot($self,'handleCircStatOwningHome');
        return 1;
    }
    else
    {
        return 0;
    }
}

sub handleLoginPage
{
print "handleLoginPage\n";
    my ($self) = @_[0];
    my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
    $body =~ s/[\r\n]//g;
    $log->addLine("Body of the HTML: " . Dumper($body));
    if( ($body =~ m/<td>Initials<\/td>/) && ($body =~ m/<td>Password<\/td>/)  )
    {
        my @forms = $driver->find_elements('//form');
        foreach(@forms)
        {
            $thisForm = $_;
            if($thisForm->get_attribute("action") =~ /\/htcircrep\/\/\-1\/\/VALIDATE/g )
            {
                my $circActivty = $driver->execute_script("
                var doms = document.getElementsByTagName('input');
                for(var i=0;i<doms.length;i++)
                {
                    var thisaction = doms[i].getAttribute('name');

                    if(thisaction.match(/NAME/g))
                    {
                        doms[i].value = '".$self->{webLogin}."';
                    }
                    if(thisaction.match(/CODE/g))
                    {
                        doms[i].value = '".$self->{webPass}."';
                    }
                }

                ");                
                $thisForm->submit();
                sleep 1;                
                takeScreenShot($self,'handleLoginPage');
            }
        }
    }
    else
    {
        print "no login page found";
    }
    return 1;  # always return true even when it doesn't prompt to login
}

sub switchToFrame
{
print "switchToFrame\n";
    my ($self) = @_[0];
    my @pageVals = @{@_[1]};
    my $frameNum = 0;
    my $hasWhatIneed = 0;
    my $tries = 0;
    my $error = 0;
    while(!$hasWhatIneed)
    {
        try
        {
            $driver->switch_to_frame($frameNum); # This can throw an error if the frame doesn't exist
            my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
            $body =~ s/[\r\n]//g;
            my $notThere = 0;
            foreach(@pageVals)
            {
            print "checking $_\n";
                $notThere = 1 if (!($body =~ m/$_/) );
            }
            if(!$notThere)
            {
                $hasWhatIneed=1;
            }
            else
            {
                $frameNum++;
            }
        }
        catch
        {
            $frameNum++;
        };
        # walk back up to the parent frame
        $driver->switch_to_frame();
        $tries++;
        my $error = 1 if $tries > 10;
        $hasWhatIneed = 1 if $tries > 10;
    }
    if(!$error)
    {
        $driver->switch_to_frame($frameNum);
    }
    return $error;
}


#### saving this JS code incase we need to deal with the page via JS instead of webcomponent
# my $circActivty = $driver->execute_script("

# var doms = document.getElementsByTagName('form');

# for(var i=0;i<doms.length;i++)
# {
# var thisaction = doms[i].getAttribute('action');

# if(thisaction.match(/\\/managerep\\/startviews\\/0\\/d\\/table_1x1/g))
# {
# doms.[i].submit();
    # //doms[i].getElementsByTagName('input')[0].click();
    # // getAttribute('class');
# }
# }

# ");


sub takeScreenShot
{
    my ($self) = shift;
    my $action = shift;
    print "writing screenshot: $screenshotDIR/".$self->{name}."_".$action."_progress.png\n";
    $driver->capture_screenshot("$screenshotDIR/".$self->{name}."_".$action."_progress.png", {'full' => 1});
}


sub figureWhichDates
{
    my ($self) = shift;
    my $monthsBack = shift || 5;
    my %alreadyScraped = ();
    
    my @months = qw( onebase Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
    my @ret = ();
    
    my $query = "
    select
    distinct
    concat(extract(year from borrow_date),'-',extract(month from borrow_date) )
    from
    $self->{prefix}"."_bnl bnl,
    $self->{prefix}"."_cluster cluster
    where
    cluster.id=bnl.owning_cluster and
    cluster.name ='".$cluster."'
    order by 1
    ";

    $log->addLine($query);
    my @results = @{$self->{dbHandler}->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $alreadyScraped{ @row[0] } = 1;
    }
    
    my $loops = 1;
    while($loops < $monthsBack)
    {
        my $query = "
        select
        concat(
        extract(year from date_sub(now(),interval $loops month)),
        '-',
        extract(month from date_sub(now(), interval $loops month))        
        ),
        right(extract(year from date_sub(now(), interval $loops month)),2),
        extract(month from date_sub(now(), interval $loops month))
        ";
        $log->addLine($query);
        my @results = @{$self->{dbHandler}->query($query)};
        foreach(@results)
        {
            my @row = @{$_};
            push @ret, "" . @months[@row[2]] . " " . @row[1] if !$alreadyScraped{ @row[0] };
        }
        $loops++;
    }

    return \@ret;
}


sub DESTROY
{
    my ($self) = @_[0];

}


1;