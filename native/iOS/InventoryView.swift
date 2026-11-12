import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var category = "全部用途"
    @State private var add = false
    var body: some View {
        List {
            Section { PageHeading(title: "每一瓶，\n各有所长。", subtitle: "记住来处，也记住每一次取用。") }
            Section {
                Picker("用途", selection: $category) { ForEach(PersonalLibrary.categories, id: \.self) { Text($0) } }
                ForEach(store.state["products"].array.filter { p in
                    (category == "全部用途" || PersonalLibrary.uses(p).contains(category)) && (query.isEmpty || ([p["brand"].text, p["name"].text, p["code"].text, p["searchTerms"].text].joined(separator: " ")).localizedCaseInsensitiveContains(query))
                }, id: \.id) { p in NavigationLink { ProductDetail(productID: p.id) } label: { ProductSummary(product: p) } }
            }
            Button("添加药剂", systemImage: "plus") { add = true }
        }.searchable(text: $query, prompt: "搜索品牌或药剂").navigationTitle("药剂").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $add) { NavigationStack { ProductEditor(product: .object(["id": .string(identifier()), "brand": .string(""), "name": .string(""), "use": .string("正洗"), "capacity": .number(500), "remaining": .number(500), "stockStatus": .string("estimated"), "price": .string("")])) } }
    }
}

struct ProductDetail: View {
    @EnvironmentObject private var store: AppStore
    let productID: String
    var snapshot: JSON? = nil
    @State private var edit = false
    @State private var usage = false
    private var product: JSON { snapshot ?? store.state["products"].array.first(where: { $0.id == productID }) ?? .null }
    var body: some View {
        List {
            Section {
                BottleView(product: product).frame(height: 210).frame(maxWidth: .infinity)
                Text(product["brand"].text).foregroundStyle(.secondary)
                Text(product["name"].text).font(.title2)
                Text(WashEngine.stockText(product)).font(.headline)
                Text("用途：\(PersonalLibrary.uses(product).joined(separator: " · ")) · \(product["capacity"].number.map { "容量 \(volume($0)) \(PersonalLibrary.unit(product))" } ?? "容量待填写")").font(.subheadline).foregroundStyle(.secondary)
                if snapshot != nil { Label("当时的药剂快照 · 只读", systemImage: "clock.arrow.circlepath") }
            }
            Section("使用方法") { Text(product["instructions"].text.isEmpty ? "尚未填写，请核对本瓶标签。" : product["instructions"].text) }
            Section("pH 记录") {
                Text(product["ph"]["value"].number.map { "pH \(volume($0)) · \(product["ph"]["medium"].text)" } ?? "pH 待填写")
                Text(product["ph"]["source"].text.isEmpty ? "尚无来源或稀释条件。" : product["ph"]["source"].text).font(.caption).foregroundStyle(.secondary)
            }
            Section("购入标签") {
                LabeledContent("购入日期", value: product["date"].text)
                LabeledContent("购入地点", value: product["place"].text)
                LabeledContent("价格", value: product["price"].number.map { "¥\(volume($0))" } ?? "未填写")
            }
            if snapshot == nil {
                Section {
                    Button("编辑这瓶药剂") { edit = true }
                    Button("记录额外取用") { usage = true }
                    Text("洗车备液已扣减的部分，不要重复记录。").font(.caption).foregroundStyle(.secondary)
                }
                Section("使用履历") {
                    ForEach(store.state["history"].array.filter { $0["productId"].text == productID || $0["amounts"][productID] != .null }, id: \.id) { h in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(h["kind"].text == "preparation" ? "流程备液 · \(h["plan"].text)" : "额外取用")
                            Text("\(volume(h["amounts"][productID].number ?? h["amount"].number ?? 0)) \(PersonalLibrary.unit(product)) · \(h["location"].text)").font(.subheadline)
                            Text(h["date"].text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle(snapshot == nil ? "药剂资料" : "历史快照").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $edit) { NavigationStack { ProductEditor(product: product) } }
            .sheet(isPresented: $usage) { NavigationStack { UsageEditor(product: product) } }
    }
}

struct ProductEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var product: JSON
    @State private var phText = ""
    @State private var priceText = ""
    @State private var capacityText = ""
    var body: some View {
        Form {
            Section("这一瓶") {
                TextField("品牌", text: textBinding($product, "brand"))
                TextField("药剂名称", text: textBinding($product, "name"))
                ForEach(Array(PersonalLibrary.categories.dropFirst()), id: \.self) { use in
                    Toggle(use, isOn: Binding(get: { PersonalLibrary.uses(product).contains(use) }, set: { on in
                        var uses = PersonalLibrary.uses(product).filter { $0 != use }; if on { uses.append(use) }
                        product["uses"] = .array(uses.map(JSON.string)); product["use"] = .string(uses.first ?? "")
                    }))
                }
                LabeledContent("容量 · \(PersonalLibrary.unit(product))") { TextField("待填写", text: $capacityText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("余量可信度", selection: textBinding($product, "stockStatus")) { Text("已核对").tag("exact"); Text("估算").tag("estimated"); Text("未知").tag("unknown") }
                if product["stockStatus"].text != "unknown" { LabeledContent("余量 · \(PersonalLibrary.unit(product))") { TextField("余量", value: numberBinding($product, "remaining"), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
            }
            Section("购入标签") {
                TextField("购入日期 · YYYY-MM-DD", text: textBinding($product, "date"))
                TextField("购入地点", text: textBinding($product, "place"))
                TextField("价格 · ¥ · 可留空", text: $priceText).keyboardType(.decimalPad)
            }
            Section("使用方法") { TextField("本瓶标签、表面限制和施工方式", text: textBinding($product, "instructions"), axis: .vertical).lineLimit(3...8) }
            Section("pH · 可留空，不能猜测") {
                TextField("0—14", text: $phText).keyboardType(.decimalPad)
                TextField("原液 / 工作液", text: Binding(get: { product["ph"]["medium"].text }, set: { product["ph"]["medium"] = .string($0) }))
                TextField("来源与稀释条件", text: Binding(get: { product["ph"]["source"].text }, set: { product["ph"]["source"] = .string($0) }), axis: .vertical)
            }
        }.navigationTitle("编辑药剂").navigationBarTitleDisplayMode(.inline)
            .onAppear { capacityText = product["capacity"].number.map { String($0) } ?? ""; phText = product["ph"]["value"].number.map(volume) ?? ""; priceText = product["price"].number.map(volume) ?? "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { store.perform {
                    guard !product["name"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !product["brand"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WashError("请填写品牌与名称。") }
                    if capacityText.isEmpty { product["capacity"] = .null }
                    else { guard let n = Double(capacityText), n > 0 else { throw WashError("请填写有效容量或留空。") }; product["capacity"] = .number(n) }
                    if !phText.isEmpty { guard let n = Double(phText), (0...14).contains(n) else { throw WashError("pH 应为 0—14 或留空。") }; product["ph"]["value"] = .number(n) }
                    else { product["ph"]["value"] = .null }
                    if !priceText.isEmpty { guard let n = Double(priceText), n >= 0 else { throw WashError("价格应为有效数值。") }; product["price"] = .number(n) }
                    else { product["price"] = .string("") }
                    if product["stockStatus"].text == "unknown" { product["remaining"] = .null }
                    product["stockUpdatedAt"] = .number(milliseconds())
                    try store.saveProduct(product); dismiss()
                } } }
            }
    }
}

struct UsageEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let product: JSON
    @State private var amount: Double = 0
    @State private var location = ""
    var body: some View {
        Form {
            Text(product["name"].text).font(.title2)
            Text(WashEngine.stockText(product))
            LabeledContent("本次取用 · \(PersonalLibrary.unit(product))") { TextField("用量", value: $amount, format: .number).keyboardType(.decimalPad) }
            TextField("使用地点", text: $location)
            Text("仅记录备液之外的额外取用。").font(.caption).foregroundStyle(.secondary)
            PrimaryButton(title: "确认记录") { store.perform { try store.commit(WashEngine.manualUsage(store.state, productID: product.id, amount: amount, location: location)); dismiss() } }
        }.navigationTitle("记录额外取用").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}
