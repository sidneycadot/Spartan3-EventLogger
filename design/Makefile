
.PHONY : clean

design.pdf : design.tex dataflow.pdf
	pdflatex design.tex
	pdflatex design.tex

dataflow.pdf : dataflow.fig
	fig2dev -L pdf dataflow.fig  dataflow.pdf

clean :
	$(RM) *~ design.pdf design.log design.aux design.toc dataflow.pdf

