import SwiftUI

/// Opens the current week's smack-talk thread from a standings screen.
struct SmackTalkButton: View {
    let context: SmackTalkContext
    var weeklyResult: WeeklyResult? = nil
    var label: String = "Smack Talk"

    var body: some View {
        NavigationLink {
            WeekSmackTalkView(context: context, weeklyResult: weeklyResult)
        } label: {
            Label(label, systemImage: "bubble.left.and.bubble.right.fill")
        }
    }
}

#if DEBUG
struct SmackTalkButton_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            List {
                SmackTalkButton(
                    context: SmackTalkDemoData.currentContext,
                    weeklyResult: DemoData.weeklyResult
                )
            }
        }
    }
}
#endif
