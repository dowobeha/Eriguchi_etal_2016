#!/usr/bin/env ducttape

task parallel
     :: url="https://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2"
      > parallel="bin/parallel"
{
	wget "${url}" -O parallel.bz2
	tar xfvj parallel.bz2 --strip-components=1
	./configure --prefix=$(pwd)
	make
	make install
}

task filter_enju
     :: repo="git@github.com:dowobeha/filter_enju.git"
     :: ref="759af906078c1b9878d3162b03a784d3345e1d21"
      > filter_enju
{
	git init
	git remote add origin "${repo}"
	git fetch
	git checkout -t origin/master
	git checkout "${ref}"

	make
}


task enju
     :: repo="git@github.com:mynlp/enju.git"
     :: ref="30841479e2bffcda5d021e1b9860836892b45640"
     :: parallel_threads=@
      > enju="bin/enju"
      > enju2ptb="enju2ptb/convert"
{
	git init
	git remote add origin "${repo}"
	git fetch
	git checkout -t origin/master
	git checkout "${ref}"

	./configure --prefix=$(pwd) --with-enju2ptb
	sed -i '/yacc.hh: yacc.h/s/^/#/g' ll/src/Makefile
	sed -i '/cp $< $@/s/^/#/g' ll/src/Makefile
	make -j ${parallel_threads}
	make install
}

task kytea
     :: url="http://www.phontron.com/kytea/download/kytea-0.4.7.tar.gz"
      > kytea="bin/kytea"
{
	wget "${url}" -O kytea.tgz
	tar xfvz kytea.tgz --strip-components=1
	./configure --prefix=$(pwd)
	make
	make install
}

task aspec
     :: corpus=(Corpus: train dev devtest test)
     :: tarball=${aspec_tgz}
     :: max_lines=${aspec_max_lines}
     :: ja_field=(Corpus: train=4 dev=3 devtest=3 test=3)
     :: en_field=(Corpus: train=5 dev=4 devtest=4 test=4)
      > en
      > ja
{
	echo "Extracting ASPEC-JE ${corpus} data from ${tarball} ..."
	tar xfvz ${tarball} ASPEC/ASPEC-JE/${corpus} --strip-components=3

	echo "Constructing tsv file for ${corpus} data..."
	# NOTE: ducttape by default halts execution on pipefail
	#       The following use of process substitution avoids pipefail from occurring
	#           in the interaction between cat and head (if cat were to be used instead)
	head -n ${max_lines} <(cat ${corpus}*.txt) | sed 's, ||| ,\t,g' > ${corpus}.tsv

	echo "Extracting Japanese side of parallel ${corpus} data..."
	cut -f ${ja_field} < ${corpus}.tsv     > ja

	echo "Extracting English side of parallel files..."
	cut -f ${en_field} < ${corpus}.tsv     > en

	echo Removing ${corpus}*.txt
	rm ${corpus}*.txt

	echo "Removing ${corpus}.tsv"
	rm ${corpus}.tsv

}

task parse
     < in=$en@aspec
     < parallel=@parallel
     < enju=@enju
     > out
     :: parallel_threads=(Corpus: train=$parallel_threads dev=1 devtest=1 test=1)
     :: max_sentence_length=${aspec_max_sentence_length}
{
#	lines_total=$(wc -l ${in} | cut -d " " -f 1)
#	echo "There are ${lines_total} lines in ${in}"

#	lines_per_part=$(( ${lines_total} / ${parallel_threads} ))
#	echo "Splitting ${in} into ${parallel_threads} parts, each containing no more than ${lines_per_part} lines"

#	suffix_length=$(echo -n "${parallel_threads}" | wc -c | cut -d " " -f 1)

#	split --lines=${lines_per_part} --numeric-suffixes --suffix-length=${suffix_length} ${in} part

	if (( ${parallel_threads} > 1 )); then
		cat ${in} | ${parallel} --pipe -j${parallel_threads} ${enju} -xml -W ${max_sentence_length} > ${out}
	else
		cat ${in} |                                          ${enju} -xml -W ${max_sentence_length} > ${out}
	fi

}




task filter
     < in_enju=$out@parse
     < in_ja=$ja@aspec
     < parallel=@parallel
     < filter_enju=@filter_enju
     > out_en="out.en"
     > out_enju="out.enju"
     > out_ja="out.ja"
     :: parallel_threads=(Corpus: train=$parallel_threads dev=1 devtest=1 test=1)
     :: max_sentence_length=(MaxLength: 50 40 30 20 10)
{
	if (( ${parallel_threads} > 1 )); then
		${parallel} --pipe -j${parallel_threads} ${filter_enju} ${in_enju} ${in_ja} ${max_sentence_length} ${out_en} ${out_enju} ${out_ja}
	else
		                                         ${filter_enju} ${in_enju} ${in_ja} ${max_sentence_length} ${out_en} ${out_enju} ${out_ja}
	fi
}

task ptb
     < in_enju=$out_enju@filter
     < enju2ptb=@enju
     > out
{
	${enju2ptb} < ${in_enju} > ${out}
}

task tokenize
     < kytea=@kytea
     < parallel=@parallel
     < in_en=$out_en@filter
     < in_ja=$out_ja@filter
     > out_en="out.en"
     > out_ja="out.ja"
    :: parallel_threads=(Corpus: train=$parallel_threads dev=1 devtest=1 test=1) 
{
	ln -s ${in_en} ${out_en}
	
	if (( ${parallel_threads} > 1 )); then
	   cat ${in_ja} | ${parallel} --pipe -j${parallel_threads} ${kytea} -out tok > ${out_ja}
	else
	   cat ${in_ja} |                                          ${kytea} -out tok > ${out_ja}
	fi
}
     

plan {
     reach parallel
     reach enju
     reach aspec via (Corpus: train dev devtest test)
     reach parse via (Corpus: train dev devtest test)
     reach filter via (Corpus: train dev devtest test) * (MaxLength: 50 20 10)
     reach tokenize via (Corpus: train dev devtest test) * (MaxLength: 50 20 10)
     reach ptb via (Corpus: train dev devtest test) * (MaxLength: 50 20 10)
}
