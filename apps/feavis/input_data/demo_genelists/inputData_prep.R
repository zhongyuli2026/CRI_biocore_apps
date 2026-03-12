# This script is used to generate various input data for demo
rm(list = ls())
library(xlsx)
# ---------
# 1. GOseq input data
library(goseq)
###################################################
### code chunk number 6: edger_1
###################################################
library(edgeR)
table.summary=read.table(system.file("extdata","Li_sum.txt",package='goseq'),
                         sep='\t',header=TRUE,stringsAsFactors=FALSE)
counts=table.summary[,-1]
rownames(counts)=table.summary[,1]
grp=factor(rep(c("Control","Treated"),times=c(4,3)))
summarized=DGEList(counts,lib.size=colSums(counts),group=grp)


###################################################
### code chunk number 7: edger_2
###################################################
disp=estimateCommonDisp(summarized)
disp$common.dispersion
tested=exactTest(disp)
topTags(tested)


###################################################
### code chunk number 8: edger_3
###################################################
genes=as.integer(p.adjust(tested$table$PValue[tested$table$logFC!=0],
                          method="BH")<.05)
names(genes)=row.names(tested$table[tested$table$logFC!=0,])
table(genes)
sigGenes <- genes[genes == 1]
write.table(x = names(sigGenes), file = 'data/sigGenes.txt', quote = F, col.names = F, row.names = F)
###################################################
### code chunk number 11: pwf
###################################################
pwf=nullp(genes,"hg19","ensGene")
head(pwf)


###################################################
### code chunk number 12: GO.wall
###################################################
GO.wall=goseq(pwf,"hg19","ensGene")
dim(GO.wall)
head(GO.wall)
write.table(x = GO.wall, file = 'data/goseq_demo_gowall_res.txt', quote = F, sep = '\t', row.names = F, col.names = T)

###################################################
### code chunk number 13: GO.samp
###################################################
GO.samp=goseq(pwf,"hg19","ensGene",method="Sampling",repcnt=1000)
dim(GO.samp)
head(GO.samp)
write.csv(x = GO.samp, file = 'data/goseq_demo_sampling_res.csv', row.names = F, col.names = T, quote = F)

###################################################
### code chunk number 16: GO.nobias
###################################################
GO.nobias=goseq(pwf,"hg19","ensGene",method="Hypergeometric")
dim(GO.nobias)
head(GO.nobias)
write.xlsx(x = GO.nobias, file = 'data/goseq_domo_nobias_res.xlsx', col.names = T, row.names = F)
# ---------

