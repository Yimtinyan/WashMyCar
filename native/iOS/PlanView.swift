import SwiftUI

func textBinding(_ value: Binding<JSON>, _ key: String) -> Binding<String> {
    Binding(get: { value.wrappedValue[key].text }, set: { value.wrappedValue[key] = .string($0) })
}
func numberBinding(_ value: Binding<JSON>, _ key: String) -> Binding<Double> {
    Binding(get: { value.wrappedValue[key].number ?? 0 }, set: { value.wrappedValue[key] = .number($0) })
}

struct PlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft: JSON = .null
    @State private var loaded = false
    @State private var editingStep: String?
    @State private var addVehicle = false
    @State private var vehicleName = ""
    @State private var saveName = ""
    @State private var saveTemplate = false
    @State private var preparation = false
    @State private var session = false
    var body: some View {
        Form {
            Section {
                PageHeading(title: "安排好，\n再出发。", subtitle: "药剂、用量和工具，都有自己的位置。")
                Menu("选择已存方案") {
                    ForEach(store.state["templates"].array, id: \.id) { template in
                        Button(template["name"].text + (template["builtIn"].flag ? " · 内置" : " · r\(Int(template["revision"].number ?? 1))")) {
                            store.perform { try store.applyTemplate(template); draft = store.state["plan"] }
                        }
                    }
                }
                TextField("方案名称", text: textBinding($draft, "name"))
                Picker("车辆", selection: Binding(get: { draft["vehicleId"].text }, set: { id in
                    if let v = store.state["vehicles"].array.first(where: { $0.id == id }) {
                        draft = draft.replacing(["vehicleId": v["id"], "vehicle": v["name"], "vehicleModel": v["modelKey"]])
                    }
                })) {
                    ForEach(store.state["vehicles"].array, id: \.id) { v in Text(v["name"].text).tag(v.id) }
                }
                Button("添加车辆") { addVehicle = true }
                TextField("洗车地点", text: textBinding($draft, "location"))
            }.disabled(store.active)
            PreparationNotes()
            Section("洗车流程 · 可拖动排序") {
                ForEach(Array(draft["steps"].array.enumerated()), id: \.element.id) { index, step in
                    Button { editingStep = step.id } label: {
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", index + 1)).foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(step["name"].text).foregroundStyle(.primary)
                                Text(step["tools"].array.map(\.text).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
                .onMove { from, to in var steps = draft["steps"].array; steps.move(fromOffsets: from, toOffset: to); draft["steps"] = .array(steps) }
                .onDelete { offsets in
                    guard draft["steps"].array.count > offsets.count else { return }
                    var steps = draft["steps"].array; steps.remove(atOffsets: offsets); draft["steps"] = .array(steps)
                }
                Button("添加步骤", systemImage: "plus") {
                    let step: JSON = .object(["id": .string(identifier()), "name": .string("新步骤"), "productId": .string(""), "amount": .number(0), "water": .number(0), "tools": .array([]), "note": .string("")])
                    draft["steps"] = .array(draft["steps"].array + [step]); editingStep = step.id
                }
            }.disabled(store.active)
            Section {
                Button("另存个人方案") { saveName = draft["name"].text; saveTemplate = true }
                if let t = store.state["templates"].array.first(where: { $0.id == draft["templateId"].text }), !t["builtIn"].flag {
                    Button("更新当前个人方案") { store.perform { try store.editPlan(draft); try store.saveTemplate(name: draft["name"].text, updating: true) } }
                }
                PrimaryButton(title: "保存并核对准备清单") { store.perform { try store.editPlan(draft); preparation = true } }
                Text("用量为示例，请按本瓶标签核对。保存方案不会扣库存。").font(.caption).foregroundStyle(.secondary)
            }.disabled(store.active)
        }.navigationTitle("本次流程").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { store.perform { try store.editPlan(draft) } }.disabled(store.active) }
                ToolbarItem(placement: .topBarLeading) { EditButton().disabled(store.active) }
            }
            .onAppear { if !loaded { draft = store.state["plan"]; loaded = true } }
            .sheet(isPresented: Binding(get: { editingStep != nil }, set: { if !$0 { editingStep = nil } })) {
                if let id = editingStep, let step = draft["steps"].array.first(where: { $0.id == id }) {
                    NavigationStack { StepEditor(step: step, products: store.state["products"].array) { changed in
                        draft["steps"] = .array(draft["steps"].array.map { $0.id == id ? changed : $0 }); editingStep = nil
                    } }
                }
            }
            .sheet(isPresented: $preparation) { NavigationStack { PreparationView { preparation = false; session = true } } }
            .navigationDestination(isPresented: $session) { SessionView() }
            .alert("添加车辆", isPresented: $addVehicle) {
                TextField("车辆名称", text: $vehicleName)
                Button("添加") { store.perform {
                    let name = vehicleName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { throw WashError("请填写车辆名称。") }
                    let v: JSON = .object(["id": .string(identifier()), "name": .string(name), "modelKey": .null])
                    try store.commit(store.state.replacing(["vehicles": .array(store.state["vehicles"].array + [v])]))
                    draft = draft.replacing(["vehicleId": v["id"], "vehicle": v["name"], "vehicleModel": .null]); vehicleName = ""
                } }
                Button("取消", role: .cancel) {}
            }
            .alert("另存个人方案", isPresented: $saveTemplate) {
                TextField("方案名称", text: $saveName)
                Button("保存") { store.perform { try store.editPlan(draft); try store.saveTemplate(name: saveName, updating: false); draft = store.state["plan"] } }
                Button("取消", role: .cancel) {}
            }
    }
}

struct StepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var step: JSON
    let products: [JSON]
    let onSave: (JSON) -> Void
    private let tools = ["PA壶", "雾化壶", "洗车桶", "洗车手套", "预洗手套", "轮毂刷", "玻璃毛巾", "长绒擦车巾", "高压水枪"]
    var body: some View {
        Form {
            Section("步骤") {
                TextField("步骤名称", text: textBinding($step, "name"))
                Picker("使用药剂", selection: textBinding($step, "productId")) {
                    Text("无需药剂").tag("")
                    ForEach(products, id: \.id) { p in Text("\(p["brand"].text) · \(p["name"].text)").tag(p.id) }
                }
                LabeledContent("取用量 · \(products.first(where: { $0.id == step["productId"].text }).map(PersonalLibrary.unit) ?? "mL")") { TextField("用量", value: numberBinding($step, "amount"), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }.disabled(step["productId"].text.isEmpty)
                LabeledContent("另加清水 · mL") { TextField("用量", value: numberBinding($step, "water"), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section("搭配工具") {
                ForEach(tools, id: \.self) { tool in
                    Toggle(tool, isOn: Binding(get: { step["tools"].array.contains(.string(tool)) }, set: { on in
                        var selected = step["tools"].array.filter { $0 != .string(tool) }; if on { selected.append(.string(tool)) }; step["tools"] = .array(selected)
                    }))
                }
            }
            Section("现场备注") { TextField("操作与冲洗要求", text: textBinding($step, "note"), axis: .vertical).lineLimit(3...8) }
        }.navigationTitle("编辑步骤").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(step) } }
            }
    }
}
