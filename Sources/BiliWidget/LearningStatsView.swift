import SwiftUI
import Charts
import TrackerCore

struct LearningDay: Identifiable {
    let date: Date
    let seconds: Double
    var id: String { StudyRecorder.dayKey(date) }
}
struct LearningStatsView: View {
    let model: WidgetModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    private var days: [LearningDay] {
        let today = Calendar.current.startOfDay(for:Date())
        return (-89...0).compactMap { offset in
            guard let date=Calendar.current.date(byAdding:.day,value:offset,to:today) else { return nil }
            return LearningDay(date:date,seconds:model.library.studyDays[StudyRecorder.dayKey(date)]?.values.reduce(0,+) ?? 0)
        }
    }
    private var courseTotals: [(String,Double)] {
        var totals: [String:Double]=[:]
        for day in model.library.studyDays.values { for (base,seconds) in day { totals[base,default:0] += seconds } }
        return totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { ($0.key,$0.value) }
    }
    var body: some View {
        let data=days, week=Array(data.suffix(7))
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("学习统计").font(.title2.bold())
                Text("2.3 · 正式版").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !embedded { Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            }
            HStack(spacing:30) {
                metric("今日",seconds:data.last?.seconds ?? 0)
                metric("近7天",seconds:week.reduce(0){$0+$1.seconds})
                metric("累计",seconds:model.library.totalStudySeconds)
            }
            Text("近7天 · 分钟").font(.headline)
            Chart(week) { day in
                BarMark(x:.value("日期",day.date,unit:.day), y:.value("分钟",day.seconds/60))
                    .foregroundStyle(model.palette.accent)
                    .accessibilityLabel(day.date.formatted(date:.abbreviated,time:.omitted))
                    .accessibilityValue("\(Int(day.seconds)) 秒")
            }.chartXAxis { AxisMarks(values:.stride(by:.day)) { _ in AxisValueLabel(format:.dateTime.weekday(.narrow)) } }
                .frame(height:135)
            Text("近90天 · 每日学习记录").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing:4) {
                    ForEach(data) { day in
                        RoundedRectangle(cornerRadius:3).fill(model.palette.accent.opacity(day.seconds > 0 ? min(1,0.25+day.seconds/3600) : 0.08))
                            .frame(width:14,height:24)
                            .help("\(day.date.formatted(date:.abbreviated,time:.omitted)) · \(studyDuration(day.seconds))")
                            .accessibilityLabel("\(day.date.formatted(date:.abbreviated,time:.omitted))，\(Int(day.seconds))秒")
                    }
                }
            }.defaultScrollAnchor(.trailing)
            Text("课程投入时长").font(.headline)
            List(courseTotals,id:\.0) { base,seconds in
                HStack {
                    Text(model.library.courses[base]?.title ?? base).lineLimit(1)
                    Spacer()
                    Text(studyDuration(seconds)).monospacedDigit()
                }
            }.frame(minHeight:80)
            Text("从2.3开始累计连续播放的估算实际时间；不补算旧记录，不把跳转或手动修改计为学习。同一时段多标签不重复累计。统计不是专注度或完整观看证明。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(embedded ? 8 : 22).frame(width:embedded ? nil : 660,height:embedded ? nil : 610).background(model.palette.background).foregroundStyle(model.palette.foreground)
        .tint(model.palette.accent).preferredColorScheme(model.palette.colorScheme)
    }
    private func metric(_ title: String, seconds: Double) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(seconds/60)) 分钟").font(.title3.bold()).monospacedDigit()
        }
    }
}

private func studyDuration(_ seconds: Double) -> String {
    let value = Int(max(0,min(1e12,seconds.isFinite ? seconds : 0)))
    return "\(value/3600)小时\(value/60%60)分钟"
}
