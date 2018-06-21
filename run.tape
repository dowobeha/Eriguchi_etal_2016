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

task aspec
     :: corpus=(Corpus: train dev devtest test)
     :: tarball=${aspec_tgz}
     :: max_lines=${aspec_max_lines}
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
	cut -f 4 < ${corpus}.tsv     > ja

	echo "Extracting English side of parallel files..."
	cut -f 5 < ${corpus}.tsv     > en

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
     :: parallel_threads=@
     :: max_sentence_length=${aspec_max_sentence_length}
{
#	lines_total=$(wc -l ${in} | cut -d " " -f 1)
#	echo "There are ${lines_total} lines in ${in}"

#	lines_per_part=$(( ${lines_total} / ${parallel_threads} ))
#	echo "Splitting ${in} into ${parallel_threads} parts, each containing no more than ${lines_per_part} lines"

#	suffix_length=$(echo -n "${parallel_threads}" | wc -c | cut -d " " -f 1)

#	split --lines=${lines_per_part} --numeric-suffixes --suffix-length=${suffix_length} ${in} part

	cat ${in} | ${parallel} --pipe -j${parallel_threads} ${enju} -xml -W ${max_sentence_length} > ${out}
}

plan {
     reach parallel
     reach enju
     reach aspec, parse via (Corpus: train dev devtest test)
}
