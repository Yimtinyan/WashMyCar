from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'research/data'
taxonomy=json.loads((DATA/'taxonomy.json').read_text(encoding='utf-8'))
cats={r[0]:r[1] for r in taxonomy['categories']}
catmap={
'CN':['U21','U17','U15','U21','U21','U08','U17','U15','U24','U21','U15','U17','U13','U13','U13','U17','U08'],
'EU':['U01/U02','U05','U18/U19','U07','U11','U02/U06','U14','U19','U02','U02/U07','U08','U22','U08','U17','U07','U01','U11','U05','U01','U20','U17/U19','U01','U09','U02'],
'GL':['U02','U05','U20','U21','U18/U17','U22','U05','U20','U03','U17','U02','U07','U13','U15','U16','U17','U11','U04/U10','U12','U16','U07']}
cnbrand=['车仆 CHIEF']*4+['标榜 BIAOBANG']*5+['固特威 Glodway']*4+['三和 SANVO']*4
globalbrands=["Meguiar's","Turtle Wax","3D Car Care","P&S","CARPRO","SOFT99","Griot's Garage"]
def links(s): return list(dict.fromkeys(re.findall(r'https://[^\s)；;]+',s)))
def plain(s):
    s=re.sub(r'\[([^\]]+)\]\(https://[^)]+\)',r'\1',s)
    return s.replace('**','').strip()
products=[]
for filename,prefix in [('china_brands.md','CN'),('europe_brands.md','EU'),('global_brands.md','GL')]:
    for line in (ROOT/'research/raw'/filename).read_text(encoding='utf-8').splitlines():
        if not re.match(r'\| '+prefix+r'\d{2} \|',line): continue
        raw=[s.strip() for s in line.strip().strip('|').split('|')]
        r=[plain(s) for s in raw]; i=int(r[0][2:])-1
        if prefix=='CN':
            brand=cnbrand[i]; name=r[1]; use=r[2]; material=r[3]; method=r[4]; ev=r[5]
            form='见官方用法；未明示时待核实'
        elif prefix=='EU':
            brand,name,form,use,part,support,restriction,method,_,ev=r[1:]
            use=use+'；作用部位：'+part; material='厂商明确支持：'+support+'。限制/未知：'+restriction
        else:
            brand=next(b for b in globalbrands if r[1].startswith(b)); name=r[1][len(brand):].strip()
            form,use,material,method,ev=r[2:]
        status='资料待复核'
        if r[0] in ['EU01','GL11']: status='配比有明确依据'
        if r[0] in ['EU15','EU18','EU19','EU23','GL13']: status='参数冲突'
        codes=catmap[prefix][i].split('/')
        category='；'.join(cats[c] for c in codes)
        if r[0]=='CN02': category='内外饰清洁（用途细分待核）';codes=[]
        if r[0]=='CN03': category='去油膜（部位待核）';codes=[]
        if r[0]=='CN12': category='内饰清洁（材质细分待核）';codes=[]
        if r[0] in ['CN07','CN16','GL16']: category='多用途内饰清洁（含织物）';codes=['U17','U19']
        products.append(dict(id=r[0],brand=brand,name=name,region_version='按名称和来源地区/版本识别；实际瓶标待核',category=category,category_ids=codes,body_part=use,material_scope=material,supply_form=form,dilution_procedure=method,evidence_level=ev,automation_status=status,sources=links(raw[-2] if prefix=='EU' else raw[-1]),checked_date='2026-10-11'))
assert len(products)==62 and len(set(p['id'] for p in products))==62
assert all(p['sources'] for p in products)
(DATA/'products.json').write_text(json.dumps(products,ensure_ascii=False,indent=2),encoding='utf-8')
src=(ROOT/'output/洗车与汽车美容药剂研究_v0.1.md').read_text(encoding='utf-8')
supp=[]
for code,title,url,desc in re.findall(r'- (S\d{2})：\[([^\]]+)\]\(([^)]+)\)。([^\n]+)',src):
    supp.append([code,title,desc,url,'2026-10-11'])
(DATA/'supplemental_sources.json').write_text(json.dumps(supp,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'products':len(products),'unique_ids':len(set(p['id'] for p in products)),'categories':len(taxonomy['categories']),'materials':len(taxonomy['materials']),'supplemental':len(supp)},ensure_ascii=False))

# Reuse the previously reviewed document layout, changing the content and link parser.
s=(ROOT/'scripts/build_plan_pdf.py').read_text(encoding='utf-8')
s=s.replace('洗车应用产品企划与需求说明_v1.0','洗车与汽车美容药剂研究_v0.1')
s=s.replace('洗车应用产品企划与需求说明','洗车与汽车美容药剂研究')
s=s.replace('v1.0  |  2026年10月11日','v0.1  |  2026年10月12日')
s=s.replace('## 1 产品概述与立项建议','## 1 研究结论与覆盖范围')
s=s.replace('洗车应用<br/>产品企划与需求说明','洗车与汽车美容<br/>药剂研究')
s=s.replace('iPhone 与 Apple Watch','品牌 · 用途 · 部位与材质 · 应用知识库')
s=s.replace('版本 v1.0　｜　2026年10月11日','版本 v0.1　｜　2026年10月12日')
s=s.replace("[('管理','爱车与药剂'),('准备','方案与配比'),('预演','步骤与清单'),('执行','手机与手表'),('记录','反馈与复用')]","[('识别','污染与目标'),('定位','部位与材质'),('筛选','具体药剂'),('核对','规则与来源'),('执行','步骤与记录')]")
s=s.replace('交付范围：产品定位、功能需求、业务规则、页面清单、技术建议、验收用例与实施路线。','20个品牌研究对象 · 62款具名产品 · 24类用途 · 20种部位材质建档情形。配套工作簿提供完整产品证据。')
s=s.replace('iPhone与Apple Watch洗车管理应用的产品需求和实施规划','汽车美容药剂的品牌、用途、材质和知识库研究')
start=s.index('def markup(t):'); end=s.index('\ndef table(rows):',start)
markup='''def markup(t):
    parts=[]
    last=0
    for m in re.finditer(r'\\[([^\\]]+)\\]\\((https://[^)]+)\\)', t):
        parts.append(html.escape(t[last:m.start()]))
        parts.append('<link href="'+html.escape(m.group(2),quote=True)+'" color="#244960">'+html.escape(m.group(1))+'</link>')
        last=m.end()
    parts.append(html.escape(t[last:]))
    t=''.join(parts)
    return re.sub(r'\\*\\*(.+?)\\*\\*',r'<b>\\1</b>',t)
'''
s=s[:start]+markup+s[end:]
(ROOT/'scripts/build_research_pdf.py').write_text(s,encoding='utf-8')
