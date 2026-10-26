import Foundation

func widgetCopy(_ english: String, _ vietnamese: String) -> String {
    Locale.current.language.languageCode?.identifier == "vi" ? vietnamese : english
}

extension WidgetTopic {
    var title: String {
        switch self {
        case .streak: widgetCopy("Order streak", "Chuỗi đặt món")
        case .cookies: "B cookies"
        case .stamps: widgetCopy("Loyalty card", "Thẻ tích điểm")
        case .reorder: widgetCopy("Order again", "Đặt lại món")
        case .lab: "Too’s Lab"
        case .today: widgetCopy("Today at Fitbites", "Hôm nay tại Fitbites")
        }
    }
}


extension WidgetSnapshot.Loyalty {
    var tooComment: String {
        switch commentIndex {
        case 1: widgetCopy("I’ve alerted the birds.", "Tôi báo cho hội chim rồi.")
        case 2: widgetCopy("We need a bigger fridge.", "Cần tủ lạnh lớn hơn rồi.")
        case 3: widgetCopy("I’m good at business.", "Tôi giỏi kinh doanh mà.")
        case 4: widgetCopy("Your spoon is packed.", "Thìa của bạn gói xong rồi.")
        case 5: widgetCopy("I’ve cancelled my plans.", "Tôi hủy hết kế hoạch rồi.")
        case 6: widgetCopy("Your reward is safe. Somewhere.", "Quà an toàn rồi. Ở đâu đó.")
        case 7: widgetCopy("Found it. No questions.", "Tìm thấy rồi. Đừng hỏi nhé.")
        case 8: widgetCopy("Spoon ready. Wings steady.", "Thìa sẵn sàng. Cánh vững vàng.")
        case 9: widgetCopy("I’ll distract Tiel. GO!", "Tôi đánh lạc hướng Tiel. ĐI!")
        default: widgetCopy("Tiel thinks you’re a regular.", "Tiel nghĩ bạn là khách quen.")
        }
    }
}
