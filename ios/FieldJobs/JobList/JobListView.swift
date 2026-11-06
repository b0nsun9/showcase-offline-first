import SwiftUI

struct JobListView: View {
    @ObservedObject var vm: JobListViewModel
    let makeDetail: (String) -> JobDetailViewModel

    var body: some View {
        NavigationView {
            List {
                if let emptyMessage = vm.emptyMessage {
                    Text(emptyMessage).foregroundColor(.secondary)
                }
                ForEach(vm.rows) { row in
                    NavigationLink(destination: JobDetailView(vm: makeDetail(row.id))) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.window).font(.subheadline)
                            Text(row.address).font(.headline)
                            Text(row.task)
                            Text(row.status).font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .refreshable { await vm.refresh() }
            // An inset, not a VStack sibling: the large title follows only a scroll view at the root.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let banner = vm.banner {
                    Text(banner)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial, ignoresSafeAreaEdges: []) // not up behind the title
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let updatedText = vm.updatedText {
                        Text(updatedText).font(.footnote)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await vm.start() }
    }
}
