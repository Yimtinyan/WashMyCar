from pathlib import Path
import re
import html
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.platypus import BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, PageBreak, LongTable, TableStyle, Flowable
from reportlab.platypus.tableofcontents import TableOfContents

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'output/洗车应用产品企划与需求说明_v1.0.md'
OUT = ROOT / 'output/pdf/洗车应用产品企划与需求说明_v1.0.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont('YaHei', 'C:/Windows/Fonts/msyh.ttc', subfontIndex=0))
pdfmetrics.registerFont(TTFont('YaHeiBold', 'C:/Windows/Fonts/msyhbd.ttc', subfontIndex=0))
pdfmetrics.registerFontFamily('YaHei',normal='YaHei',bold='YaHeiBold',italic='YaHei',boldItalic='YaHeiBold')
W, H = A4
M = 48
CW = W - M*2
INK = colors.HexColor('#000000')
MUTED = colors.HexColor('#586473')
ACCENT = colors.HexColor('#244960')
styles = {
 'body': ParagraphStyle('Body',fontName='YaHei',fontSize=10.4,leading=16.4,textColor=INK,wordWrap='CJK',spaceAfter=8),
 'h1': ParagraphStyle('H1',fontName='YaHeiBold',fontSize=17,leading=24,spaceBefore=18,spaceAfter=11,keepWithNext=True,wordWrap='CJK'),
 'h2': ParagraphStyle('H2',fontName='YaHeiBold',fontSize=12,leading=18,spaceBefore=11,spaceAfter=7,keepWithNext=True,wordWrap='CJK'),
 'cell': ParagraphStyle('Cell',fontName='YaHei',fontSize=9.1,leading=13.7,wordWrap='CJK'),
 'cellhead': ParagraphStyle('CellHead',fontName='YaHeiBold',fontSize=9.1,leading=13.7,wordWrap='CJK',textColor=colors.white),
 'small': ParagraphStyle('Small',fontName='YaHei',fontSize=9,leading=14,wordWrap='CJK',textColor=MUTED,spaceAfter=8),
 'ref': ParagraphStyle('Ref',fontName='YaHei',fontSize=9.3,leading=15,wordWrap='CJK',spaceAfter=10),
 'title': ParagraphStyle('Title',fontName='YaHeiBold',fontSize=26,leading=38,spaceAfter=16,wordWrap='CJK'),
}

class Journey(Flowable):
    def __init__(self):
        Flowable.__init__(self)
        self.width=CW
        self.height=75
    def draw(self):
        c=self.canv
        labels=[('管理','爱车与药剂'),('准备','方案与配比'),('预演','步骤与清单'),('执行','手机与手表'),('记录','反馈与复用')]
        bw=(CW-4*13)/5
        for i,(a,b) in enumerate(labels):
            x=i*(bw+13)
            c.setFillColor(colors.HexColor('#EDF2F5'))
            c.setStrokeColor(colors.HexColor('#CBD5DE'))
            c.roundRect(x,13,bw,51,5,fill=1,stroke=1)
            c.setFillColor(INK)
            c.setFont('YaHeiBold',11)
            c.drawCentredString(x+bw/2,44,a)
            c.setFont('YaHei',8.4)
            c.drawCentredString(x+bw/2,27,b)
            if i<4:
                c.setStrokeColor(ACCENT)
                c.line(x+bw+2,38,x+bw+11,38)
                c.line(x+bw+8,41,x+bw+11,38)
                c.line(x+bw+8,35,x+bw+11,38)

class PlanDoc(BaseDocTemplate):
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        self.heading_count=0
        frame=Frame(M,48,CW,H-98,leftPadding=0,bottomPadding=0,rightPadding=0,topPadding=0)
        self.addPageTemplates(PageTemplate(id='normal',frames=frame,onPage=self.decorate))
    def beforeDocument(self):
        self.heading_count=0
    def decorate(self,c,doc):
        c.saveState()
        if doc.page>1:
            c.setFont('YaHei',8)
            c.setFillColor(MUTED)
            c.drawString(M,H-30,'洗车应用产品企划与需求说明')
            c.drawRightString(W-M,H-30,'v1.0  |  2026年10月11日')
        c.setFont('YaHei',8)
        c.setFillColor(MUTED)
        c.drawRightString(W-M,28,str(doc.page))
        c.restoreState()
    def afterFlowable(self,f):
        if isinstance(f,Paragraph) and f.style.name=='H1':
            self.heading_count+=1
            key='chapter'+str(self.heading_count)
            title=f.getPlainText()
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(title,key,0,False)
            self.notify('TOCEntry',(0,title,self.page,key))

def markup(t):
    t=html.escape(t)
    t=re.sub(r'(https://[^\s]+)',lambda m:f'<link href="{m.group(1)}" color="#244960">{m.group(1)}</link>',t)
    t=re.sub(r'\*\*(.+?)\*\*',r'<b>\1</b>',t)
    return t

def table(rows):
    n=len(rows[0])
    lens=[sum(min(len(r[i]),70) for r in rows)/len(rows) for i in range(n)]
    # Compact identifiers and statuses; reserve width for explanations.
    if n==3:
        weights=[0.25,0.38,0.37]
    elif n==4:
        if rows[0][0]=='编号' and len(rows[0])>2 and rows[0][2]=='当前建议':
            weights=[0.09,0.29,0.38,0.24]
        elif rows[0][0] in ['需求ID','编号']:
            weights=[0.12,0.39,0.13,0.36]
        elif rows[0][0]=='输入':
            weights=[0.49,0.17,0.17,0.17]
        elif rows[0][0]=='阶段':
            weights=[0.23,0.14,0.34,0.29]
        else:
            weights=[0.23,0.27,0.24,0.26]
    elif n==2:
        weights=[0.25,0.75]
    else:
        weights=[1/n]*n
    if rows[0][0]=='实体': weights=[0.23,0.41,0.36]
    if rows[0][0]=='风险': weights=[0.31,0.09,0.60]
    if rows[0][0]=='类别': weights=[0.17,0.43,0.40]
    if rows[0][0]=='页面ID': weights=[0.12,0.24,0.64]
    if rows[0][0]=='工作包': weights=[0.22,0.32,0.21,0.25]
    data=[[Paragraph(markup(v),styles['cellhead' if j==0 else 'cell']) for v in r] for j,r in enumerate(rows)]
    tab=LongTable(data,colWidths=[CW*x for x in weights],repeatRows=1,hAlign='LEFT',spaceBefore=3,spaceAfter=12)
    commands=[('BACKGROUND',(0,0),(-1,0),ACCENT),('GRID',(0,0),(-1,-1),0.45,colors.HexColor('#D9D9D9')),('VALIGN',(0,0),(-1,-1),'MIDDLE'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7)]
    for j in range(1,len(rows)):
        commands.append(('BACKGROUND',(0,j),(-1,j),colors.white if j%2 else colors.HexColor('#F3F6F8')))
    tab.setStyle(TableStyle(commands))
    return tab

src=SOURCE.read_text(encoding='utf-8')
intro,body=src.split('## 1 产品概述与立项建议',1)
story=[Spacer(1,54),Paragraph('洗车应用<br/>产品企划与需求说明',styles['title']),Paragraph('iPhone 与 Apple Watch',styles['h2']),Paragraph('版本 v1.0　｜　2026年10月11日',styles['small']),Spacer(1,20)]
for p in intro.split('\n\n')[2:]:
    if p.strip(): story.append(Paragraph(markup(p.strip()),styles['body']))
story += [Spacer(1,16),Journey(),Spacer(1,12),Paragraph('交付范围：产品定位、功能需求、业务规则、页面清单、技术建议、验收用例与实施路线。',styles['small']),PageBreak(),Paragraph('目录',styles['title'])]
toc=TableOfContents()
toc.levelStyles=[ParagraphStyle('TOC',fontName='YaHei',fontSize=10.4,leading=17.8,spaceBefore=0,wordWrap='CJK',rightIndent=12)]
story += [toc,PageBreak()]
lines=('## 1 产品概述与立项建议'+body).splitlines()
i=0
while i<len(lines):
    line=lines[i].strip()
    if not line: i+=1; continue
    if line.startswith('|'):
        rows=[]
        while i<len(lines) and lines[i].strip().startswith('|'):
            row=[c.strip() for c in lines[i].strip().strip('|').split('|')]
            if not all(re.fullmatch(r'[-: ]+',x or '-') for x in row): rows.append(row)
            i+=1
        story.append(table(rows))
        continue
    if line.startswith('## '):
        if line.startswith('## 附录'):
            story.append(PageBreak())
        story.append(Paragraph(markup(line[3:]),styles['h1']))
    elif line.startswith('### '):
        story.append(Paragraph(markup(line[4:]),styles['h2']))
    elif line.startswith('- '):
        story.append(Paragraph(markup(line[2:]),styles['ref']))
    else:
        story.append(Paragraph(markup(line),styles['body']))
    i+=1

doc=PlanDoc(str(OUT),pagesize=A4,title='洗车应用产品企划与需求说明',author='产品企划',subject='iPhone与Apple Watch洗车管理应用的产品需求和实施规划',allowSplitting=1)
doc.multiBuild(story)
print(OUT)
