import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
const dir=fileURLToPath(new URL('.',import.meta.url));
const rows=[
['车身清洗','考赫 AFS ×2','Active Foam Spring',9.5,'泡沫预洗、手工洗车；清除一般道路污垢','碱性。AF 春日香型延伸款；勿干结','厂家已核实','https://www.koch-chemie.com/pdf/datasheet/Active_Foam_Spring_es.pdf'],
['车身清洗','考赫 GSF','Gentle Snow Foam',7.5,'日常维护洗、泡沫预洗及手套接触洗','接近中性。适合蜡／封体车辆维护','厂家已核实','https://www.koch-chemie.com/pdf/datasheet/Gentle_Snow_Foam_en.pdf'],
['车身清洗','考赫 AA','Acid Shampoo A',1,'酸性洗车工序；结合硬水成分、抑制水垢','强酸性原液。官方定位自动洗车计量系统；勿当即用型除水斑剂','厂家已核实','https://www.koch-chemie.com/pdf/datasheet/Acid_Shampoo_A_en.pdf'],
['强力清洁','考赫 GS','Green Star',12.5,'按比例稀释处理外部重污、油污及耐受表面','强碱性原液。避免热表面、干结；敏感内饰慎用','厂家已核实','https://www.koch-chemie.com/media/files/KCX-Katalog-2021-DE-web.pdf'],
['专项去污','火球柏油清洁','Tar Remover','未查到可靠值','局部柏油、沥青黑点及道路污染清除','局部施工；膜面、塑料先测试；处理后清洗残留','用途已核实；中文名对应型号','https://www.fireballkorea.com/cleaners/tar-remover'],
['专项去污','火球液体粘土','Wax Off','未查到可靠值','打蜡／封体前深度清洁，去旧蜡、油性残留和部分保护层','会削弱或移除保护层；非铁粉剂，不作为日常维护洗','国内商品名对应 Wax Off；厂家用途已核实','https://www.fireballkorea.com/cleaners/wax-off\nhttps://www.jd.com/xinghao/6728925aa506a0126acf.html'],
['专项去污','师匠青花素','疑似 S-666A 花青素','未查到可靠值','疑似水渍／水垢专项清洁剂','公开商品标题指向“花青素”；未找到厂家资料，不能据此确认材质范围与配比','型号为检索推定；非厂家确认','https://www.jd.com/jiage/1315f9917eb95fbde978.html\nhttps://www.bilibili.com/video/BV1E1421y7aM/'],
['玻璃清洁','考赫 GC','Glass Cleaner','6–8','车窗内外日常污渍、指印及轻度油污','接近中性。日常擦玻璃；与专项去油膜区分','厂家安全资料已核实','https://media.koch-chemie.com/pdf/SDBL/Glass_Cleaner_302999_1.0.0_GB_EN.pdf'],
['玻璃清洁','火球玻璃清洁','Glass','未查到可靠值','车窗内外日常清洁，擦去污渍、指印','与 GC 用途重叠；屏幕／特殊涂层不直接套用玻璃用法','用途已核实；中文名对应型号','https://www.fireballkorea.com/cleaners/glass'],
['玻璃专项','乘境 17 去油膜','17 去油膜','未查到可靠值','按用户清单定位：玻璃油膜专项处理','未检索到可核实的产品说明；研磨性、镀膜兼容性和施工参数不作推断','按用户产品名称归类；无可核实网页','无可靠公开产品资料'],
['内饰清洁','火球内饰清洁','未锁定版本；现售有 Nappa Cleaner','未查到可靠值','内饰污垢、人体油脂清洁；具体材料范围按版本','火球有新旧产品线；不能将 Nappa 参数直接套给所有版本','分类按中文名；Nappa 为厂家参考型号','https://www.fireballkorea.com/cleaners/nappa-cleaner'],
['内饰清洁','P&S XPR','按常用简称对应 XPRESS Interior Cleaner','未查到可靠值','皮革、塑料、乙烯基、橡胶等内饰的日常污垢及油脂','清洁用途；不等同长效养护，特殊屏幕／翻毛皮先核实兼容性','XPRESS 用途已核实；简称对应推定','https://psdetailproducts.com/products/xpress-interior-cleaner-doubleblack-collection'],
['内饰养护','火球内饰养护','未锁定版本','未查到可靠值','内饰清洁后养护；具体可用材料按该版本','未能唯一对应型号；不推定可用于真皮、屏幕或方向盘','按用户中文名归类；型号未锁定','https://www.fireballkorea.com/'],
['轮胎清洁','卡普 ReTyre','CARPRO ReTyre','高 pH；未核实具体值','深洗轮胎侧壁，去褐色污染、积垢及旧轮胎养护剂','强清洁定位。避免干结；流到轮毂处及时用水稀释冲洗','厂家确认高 pH；未采用商家数值','https://carpro.global/product/retyre/'],
['轮胎养护','火球蓝丝绸轮胎蜡','按名称对应 Tire Satin','不适用（油基）','清洁干燥后的轮胎侧壁养护，丝绸／缎面外观','薄涂、充分干燥后行驶；避开胎面及刹车','厂家确认 Satin 为油基；中文版本对应推定','https://www.fireballkorea.com/dressings/satin'],
['外饰养护','考赫 PSS','Plast Star silicone-free','不适用（溶剂型）','外部未喷漆塑料、橡胶密封条、轮胎侧壁养护','在清洁干燥表面施工；避开方向盘、踏板、胎面','厂家已核实','https://kcxusa.com/products/plast-star-silicone-free-1l']
];
const wb=Workbook.create();const sh=wb.worksheets.add('药剂用途清单');sh.showGridLines=false;
sh.getRange('A2').values=[['我的洗车坊 · 药剂用途清单']];
sh.getRange('A3').values=[['pH 为厂家产品值，非稀释后实测值；“未查到”表示没有可靠参数，不能视为中性。核查日期：2026-10-12']];
sh.getRange('A5:H21').values=[['用途分类','现有药剂','对应产品／型号','pH','适用场景','使用要点','核实情况','资料来源'],...rows];
sh.getRange('A2:H21').format.font={name:'Arial',size:11,color:'#243247'};
sh.getRange('A2').format.font={name:'Arial',size:16,bold:true,color:'#182C46'};
sh.getRange('A3').format.font={name:'Arial',size:10,color:'#526173'};
sh.getRange('A3').format.wrapText=false;
sh.getRange('A5:H5').format={fill:'#253F60',font:{name:'Arial',size:11,bold:true,color:'#FFFFFF'},rowHeight:28,horizontalAlignment:'center',verticalAlignment:'center'};
sh.getRange('A6:H21').format.wrapText=true;sh.getRange('A6:H21').format.verticalAlignment='center';sh.getRange('A6:H21').format.rowHeight=64;
const widths=[100,164,215,155,285,330,225,480];
for(let c=0;c<8;c++)sh.getRangeByIndexes(4,c,17,1).format.columnWidthPx=widths[c];
for(let r=6;r<=21;r++)if(r%2===0)sh.getRange(`A${r}:H${r}`).format.fill='#F2F5F9';
sh.getRange('D6:D21').format.horizontalAlignment='center';
sh.getRange('B6:B21').format.font.bold=true;
sh.getRange('A12:H12').format.fill='#FFF5DF';sh.getRange('A15:H15').format.fill='#FFF5DF';sh.getRange('A18:H18').format.fill='#FFF5DF';
const t=sh.tables.add('A5:H21',true,'Chemicals');t.showFilterButton=true;
sh.freezePanes.freezeRows(5);
wb.recalculate();
console.log((await wb.inspect({kind:'region',sheetId:sh.name,range:'A5:H21',maxChars:1800,tableMaxRows:4,tableMaxCols:8})).ndjson);
const preview=await wb.render({sheetName:sh.name,range:'A1:F21',scale:1,format:'png'});await fs.writeFile(`${dir}/preview.png`,new Uint8Array(await preview.arrayBuffer()));
const xlsx=await SpreadsheetFile.exportXlsx(wb);await xlsx.save(`${dir}/洗车药剂用途分类.xlsx`);
console.log('Exported 16 products.');
