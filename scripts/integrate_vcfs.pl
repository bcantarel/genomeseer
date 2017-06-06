#!/usr/bin/perl -w
#integrate_datasets.pl

my $refdir = '/project/shared/bicf_workflow_ref/GRCh38/';

open OM, "</project/shared/bicf_workflow_ref/GRCh38/validation.genelist.txt" or die $!;
while (my $line = <OM>) {
  chomp($line);
  $keep{$line} = 1;
}

my ($subject,$samplename,$tumorid,$somatic,$rnaseqid) = @ARGV;
my %rnaseqct;
my $inputdir = "/project/PHG/PHG_Clinical/validation/$subject";
system("tabix -f $inputdir\/$tumorid/$tumorid\.annot.vcf.gz");
if ($rnaseqid ne 'no_rnaseq') {
  open RNACT, "<$inputdir\/$rnaseqid\/$rnaseqid\.cts" or die $!;
  while (my $line = <RNACT>) {
    chomp($line);
    next if ($line =~ m/^#|Geneid/);
    my ($geneid,$chr,$start,$end,$strand,$length,$ct) = split(/\t/,$line);
    $rnaseqct{$geneid} = $ct if ($ct);
    $rnaseqct{'total'} += $ct if ($ct);
  }
  close RNACT;
  open RNACT, "<$inputdir\/$rnaseqid\/$rnaseqid\.fpkm.txt" or die $!;
  while (my $line = <RNACT>) {
    chomp($line);
    next if ($line =~ m/^#|Geneid|FPKM/);
    my ($ensid,$gene,$chr,$strand,$start,$end,$cov,$fpkm,$tmp) = split(/\t/,$line);
    $fpkm{$gene} = $fpkm if ($fpkm > 1);
  }
  close RNACT;
  
  system("zcat $inputdir\/$rnaseqid\/$rnaseqid\.annot.vcf.gz | perl -p -e 's/^/chr/' |perl -p -e 's/chr#/#/' |bgzip > $inputdir\/$rnaseqid\/$rnaseqid\.annot.chr.vcf.gz");
  system("tabix $inputdir\/$rnaseqid\/$rnaseqid\.annot.chr.vcf.gz");
  system("bcftools isec -p $inputdir\/rnaoverlap --nfiles =2 $inputdir\/$rnaseqid\/$rnaseqid\.annot.chr.vcf.gz $inputdir\/$tumorid/$tumorid\.annot.vcf.gz");
  open RNAOV, "<$inputdir\/rnaoverlap/sites.txt" or die $!;
  while (my $line = <RNAOV>) {
    chomp($line);
    my ($chr,$pos,$ref,$alt,$overlap) = split(/\t/,$line);
    $rnaval{$chr}{$pos} = 1;
  }
}
if ($somatic ne 'no_normal') {
  open IN, "gunzip -c $inputdir\/somatic/$somatic\.annot.vcf.gz |" or die $!;
 W1:while (my $line = <IN>) {
    chomp($line);
    if ($line =~ m/^#CHROM/) {
      my @header = split(/\t/,$line);
      ($chrom, $pos,$id,$ref,$alt,$score,
       $filter,$info,$format,@gtheader) = split(/\t/, $line);
    }
    if ($line =~ m/^#/) {
      next;
    }
    my ($chrom, $pos,$id,$ref,$alt,$score,
	$filter,$annot,$format,@gts) = split(/\t/, $line);
    next if ($ref =~ m/\./ || $alt =~ m/\./ || $alt=~ m/,X/);
    my %hash = ();
    foreach $a (split(/;/,$annot)) {
      my ($key,$val) = split(/=/,$a);
      $hash{$key} = $val unless ($hash{$key});
    }
    my %fail;
    $fail{'UTSWBlacklist'} = 1 if ($hash{UTSWBlacklist});
    my $exacaf = '';
    if ($hash{AC_POPMAX} && $hash{AN_POPMAX}) {
	@exacs = split(/,/,$hash{AC_POPMAX});
	my $ac = 0;
	foreach $val (@exacs) {
	    $ac += $val if ($val =~ m/^\d+$/);
	}
	@exans = split(/,/,$hash{AN_POPMAX});
	my $an = 0;
	foreach $val (@exans) {
	    $an += $val if ($val =~ m/^\d+$/);
	}
	$exacaf = sprintf("%.4f",$ac/$an) if ($ac > 0 && $an > 10);
    }
    unless ($exacaf eq '' || $exacaf <= 0.01) {
	$fail{'COMMON'} = 1;
      }
    my $cosmicsubj = 0;
    if ($hash{CNT}) {
      my @cosmicct = split(/,/,$hash{CNT}); 
      foreach $val (@cosmicct) {
	$cosmicsubj += $val if ($val =~ m/^\d+$/);
      }
    }
    my @maf;
    my @dp;
    my @ao;
    my @genotypes = @gts;
    my @deschead = split(/:/,$format);
  F1:foreach my $subjid (@gtheader) {
      my $allele_info = shift @gts;
      @ainfo = split(/:/, $allele_info);
      my %gtinfo = ();
      my @mutallfreq = ();
      foreach my $k (0..$#ainfo) {
	  $gtinfo{$deschead[$k]} = $ainfo[$k];
      }
      next W1 if ($gtinfo{DP} < 10);
      my @altct = split(/,/,$gtinfo{AO});
      foreach  my $act (@altct) {
	push @mutallfreq, sprintf("%.4f",$act/$gtinfo{DP});
      }
      push @dp, $gtinfo{DP};
      push @maf, \@mutallfreq;
      my @sortao = sort {$b <=> $a} @altct;
      push @ao, $sortao[0];
    }
    if ($gtheader[1] eq $tumorid) {
      @maf = reverse(@maf);
      @dp = reverse(@dp);
      @ao = reverse(@ao);
      @genotypes = reverse(@genotypes);
    }
    $hash{AF} = join(",",@{$maf[0]});
    $hash{NormalAF} =  join(",",@{$maf[1]});
    $hash{DP} = $dp[0];
    $hash{NormalDP} = $dp[1];
    next if ($maf[1][0] > 0.005 || $maf[1][0]*5 > $maf[0][0]);
    my $newgt = $genotypes[0];
    foreach (@dp) {
	$fail{'LowDepth'} = 1 if ($_ < 20);
    }
    my @callers = split(/,/,$hash{CallSet});
    if ($id =~ m/COS/ && $cosmicsubj >= 5) {
	$fail{'LowAltCt'} = 1 if ($ao[0] < 3);
	$fail{'LowMAF'} = 1 if ($maf[0][0] < 0.01);
    }else {
	$fail{'OneCaller'} = 1 if (scalar(@callers) < 2);
	$fail{'LowAltCt'} = 1 if ($ao[0] < 8);
	$fail{'LowMAF'} = 1 if ($maf[0][0] < 0.05);
    }
    if ($rnaval{$chrom}{$pos}) {
	$hash{RnaSeqValidation} = 1;
    } 
    $hash{Somatic} = 1;
    $hash{SomaticCallSet}=$hash{CallSet};
    foreach $trx (split(/,/,$hash{ANN})) {
	my ($allele,$effect,$impact,$gene,$geneid,$feature,
	    $featureid,$biotype,$rank,$codon,$aa,$pos_dna,$len_cdna,
	    $cds_pos,$cds_len,$aapos,$aalen,$distance,$err) = split(/\|/,$trx);
	next unless $keep{$gene};
	if ($rnaseqct{$gene} && $rnaseqct{$gene} > 10) {
	    $hash{logcpm}=sprintf("%.1f",log2(1000000*$rnaseqct{$gene}/$rnaseqct{'total'}));
	} if ($fpkm{$gene}) {
	    $hash{fpkm} = sprintf("%.1f",$fpkm{$gene});
	}
	my @fail = keys %fail;
	if (scalar(@fail) == 0) {
	    $filter = 'PASS';
	}else {
	    $filter = join(";", 'FailedQC',@fail);
	}
	my @nannot;
	foreach $info (sort {$a cmp $b} keys %hash) {
	    if ($hash{$info}) {
		push @nannot, $info."=".$hash{$info} 
	    }else {
		push @nannot, $info;
	    }
	}
	$newannot = join(";",@nannot);
	$somline{$chrom}{$pos} = [$chrom, $pos,$id,$ref,$alt,$score,
				  $filter,$newannot,$format,$newgt];
	next W1;
    }
 }
}
close IN;

open IN, "gunzip -c $inputdir\/$tumorid/$tumorid\.annot.vcf.gz|" or die $!;
open OUT, ">$inputdir\/$tumorid\.final.vcf" or die $!;
my %done;
while (my $line = <IN>) {
  chomp($line);
  if ($line =~ m/^#CHROM/) {
    my @header = split(/\t/,$line);
    ($chrom, $pos,$id,$ref,$alt,$score,
     $filter,$info,$format,@gtheader) = split(/\t/, $line);
  }
  if ($line =~ m/^#/) {
    print OUT $line,"\n";
    next;
  }
  my ($chrom, $pos,$id,$ref,$alt,$score,
      $filter,$annot,$format,@gts) = split(/\t/, $line);
  next if ($ref =~ m/\./ || $alt =~ m/\./ || $alt=~ m/,X/);
  my %hash = ();
  foreach $a (split(/;/,$annot)) {
    my ($key,$val) = split(/=/,$a);
    $hash{$key} = $val unless ($hash{$key});
  }
  my %fail;
  $fail{'UTSWBlacklist'} = 1 if ($hash{UTSWBlacklist});
  my $exacaf = '';
  if ($hash{AC_POPMAX} && $hash{AN_POPMAX}) {
    @exacs = split(/,/,$hash{AC_POPMAX});
    my $ac = 0;
    foreach $val (@exacs) {
      $ac += $val if ($val =~ m/^\d+$/);
    }
    @exans = split(/,/,$hash{AN_POPMAX});
    my $an = 0;
    foreach $val (@exans) {
      $an += $val if ($val =~ m/^\d+$/);
    }
    $exacaf = sprintf("%.4f",$ac/$an) if ($ac > 0 && $an > 10);
  }
  unless ($exacaf eq '' || $exacaf <= 0.01) {
    $fail{'COMMON'} = 1;
  }
  my @deschead = split(/:/,$format);
  my $allele_info = $gts[0];
  @ainfo = split(/:/, $allele_info);
  foreach my $k (0..$#ainfo) {
      $hash{$deschead[$k]} = $ainfo[$k];
    }
  my $cosmicsubj = 0;
  if ($hash{CNT}) {
    my @cosmicct = split(/,/,$hash{CNT}); 
    foreach $val (@cosmicct) {
      $cosmicsubj += $val if ($val =~ m/^\d+$/);
    }
  }
  my @altct = split(/,/,$hash{AO});
  my $totalaltct = 0;
  foreach  my $act (@altct) {
      $totalaltct += $act;
  }
  if ($hash{DP} =~ m/,/) {
      $hash{DP} = $totalaltct+$hash{RO};
  }
  next unless ($hash{DP});
  my @mutallfreq;
  foreach  my $act (@altct) {
      push @mutallfreq, sprintf("%.4f",$act/$hash{DP});
  }
  my @sortao = sort {$b <=> $a} @altct;
  $hash{AF} = join(",",@mutallfreq);
  if ($hash{DP} < 20) {
    $fail{'LowDepth'} = 1;
  }
  my @callers = split(/,/,$hash{CallSet});
  if ($somval{$chrom}{$pos}) {
      push @callers, split(/,/,$somval{$chrom}{$pos});
  }
  if ((grep(/hotspot/,@callers) || $id =~ m/COS/) && $cosmicsubj >= 5) {
      $fail{'LowAltCt'} = 1 if ($altct[0] < 3);
      $fail{'LowMAF'} = 1 if ($mutallfreq[0] < 0.01);
  }else {
      $fail{'OneCaller'} = 1 if (scalar(@callers) < 2);
      $fail{'LowAltCt'} = 1 if ($altct[0] < 8);
      $fail{'LowMAF'} = 1 if ($mutallfreq[0] < 0.05);
  }
  my $keepforvcf = 0;
  my @aa;
  next unless ($hash{ANN});
  foreach $trx (split(/,/,$hash{ANN})) {
    my ($allele,$effect,$impact,$gene,$geneid,$feature,
	$featureid,$biotype,$rank,$codon,$aa,$pos_dna,$len_cdna,
	$cds_pos,$cds_len,$aapos,$aalen,$distance,$err) = split(/\|/,$trx);
    next unless ($impact =~ m/HIGH|MODERATE/);
    next unless $keep{$gene};
    push @aa, $aa if ($aa ne '');
    $keepforvcf = $gene;
  }
  next unless $keepforvcf;
  my @fail = keys %fail;
  if (scalar(@fail) < 1) {
    $filter = 'PASS';
  }elsif (scalar(@fail) > 0) {
    $filter = join(";", 'FailedQC',@fail);
  }else {
    next;
  }
  if ($rnaseqct{$keepforvcf} && $rnaseqct{$keepforvcf} > 10) {
    $hash{logcpm}=sprintf("%.1f",log2(1000000*$rnaseqct{$keepforvcf}/$rnaseqct{'total'}));
  } if ($fpkm{$keepforvcf}) {
    $hash{fpkm} = sprintf("%.1f",$fpkm{$keepforvcf});
  } if ($rnaval{$chrom}{$pos}) {
    $hash{RnaSeqValidation} = 1;
  } if ($somval{$chrom}{$pos}) {
    $hash{Somatic} = 1;
    $hash{SomaticCallSet}=$somval{$chrom}{$pos};
  }
  my @nannot;
  foreach $info (sort {$a cmp $b} keys %hash) {
    if ($hash{$info}) {
      push @nannot, $info."=".$hash{$info} 
    }else {
      push @nannot, $info;
    }
  }
  $newannot = join(";",@nannot);
  $done{$chrom}{$pos} = 1;
  print OUT join("\t",$chrom, $pos,$id,$ref,$alt,$score,
		 $filter,$newannot,$format,$allele_info),"\n";
}

foreach my $chrom (keys %somline) {
    foreach my $pos (keys %{$somline{$chrom}}) {
    next if $done{$chrom}{$pos};
    print OUT join("\t",@{$somline{$chrom}{$pos}}),"\n";
  }
}
close OUT;

system("vcf-sort $inputdir\/$tumorid\.final.vcf | bgzip > $inputdir\/$subject\.philips.vcf.gz");
system("rm $inputdir\/$tumorid\.final.vcf");
system("rm -fr $inputdir\/rnaoverlap");

sub log2 {
  my $n = shift;
  return log($n)/log(10);
}