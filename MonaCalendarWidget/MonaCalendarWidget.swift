//
//  MonaCalendarWidget.swift
//  MonaCalendarWidget
//

import CoreGraphics
import Foundation
import SwiftUI
import WidgetKit

private enum MonaCalendarWidgetConstants {
    static let kind = "com.kekeeya.Mona.CalendarWidget"
}

private enum MonaCalendarWidgetBackgroundStyle: String {
    case transparent
    case black
    case border
}

private struct MonaCalendarWidgetEntry: TimelineEntry {
    let date: Date
    let content: CalendarHUDContent
    let image: CGImage?
    let backgroundStyle: MonaCalendarWidgetBackgroundStyle
}

private struct MonaCalendarWidgetProvider: TimelineProvider {
    let backgroundStyle: MonaCalendarWidgetBackgroundStyle

    func placeholder(in context: Context) -> MonaCalendarWidgetEntry {
        Self.makeEntry(weather: .sunny,
                       family: context.family,
                       backgroundStyle: backgroundStyle)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (MonaCalendarWidgetEntry) -> Void) {
        completion(Self.makeEntry(weather: Self.cachedWeather,
                                  family: context.family,
                                  backgroundStyle: backgroundStyle))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<MonaCalendarWidgetEntry>) -> Void) {
        let entry = Self.makeEntry(weather: Self.cachedWeather,
                                   family: context.family,
                                   backgroundStyle: backgroundStyle)
        completion(Timeline(entries: [entry],
                            policy: .after(Self.nextReloadDate(after: entry.date))))
    }

    private static func makeEntry(weather: CalendarWeatherKind,
                                  family: WidgetFamily,
                                  backgroundStyle: MonaCalendarWidgetBackgroundStyle) -> MonaCalendarWidgetEntry {
        var content = CalendarHUDContent.now(weather: weather)
        content.frame = 1
        let width = renderWidth(for: family)
        let image = CalendarHUDRenderer.renderCG(content, width: width, scale: 2)
            .map { MonaCalendarWidgetImageTrimmer.trimmingTransparentEdges($0, padding: 20) }
        return MonaCalendarWidgetEntry(date: Date(),
                                       content: content,
                                       image: image,
                                       backgroundStyle: backgroundStyle)
    }

    private static var cachedWeather: CalendarWeatherKind {
        if let stored = UserDefaults.standard.string(forKey: "MonaCalendarWeather"),
           let weather = CalendarWeatherKind(rawValue: stored) {
            return weather
        }
        return .sunny
    }

    private static func renderWidth(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 180
        case .systemMedium:
            return 320
        case .systemLarge:
            return 380
        default:
            return 320
        }
    }

    private static func nextReloadDate(after date: Date) -> Date {
        let weatherRefresh = date.addingTimeInterval(30 * 60)
        return min(weatherRefresh, nextVisualChange(after: date))
    }

    private static func nextVisualChange(after date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        var candidates = [Date]()
        for hour in [5, 9, 11, 14, 18] {
            if let candidate = calendar.date(bySettingHour: hour,
                                             minute: 0,
                                             second: 0,
                                             of: date),
               candidate > date {
                candidates.append(candidate)
            }
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
            candidates.append(midnight)
        }
        return candidates.min() ?? date.addingTimeInterval(30 * 60)
    }
}

private enum MonaCalendarWidgetImageTrimmer {
    static func trimmingTransparentEdges(_ image: CGImage, padding: Int) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let cropRect = pixels.withUnsafeMutableBytes { buffer -> CGRect? in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return nil
            }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            let bytes = buffer.bindMemory(to: UInt8.self)
            var minX = width
            var minY = height
            var maxX = -1
            var maxY = -1

            for y in 0..<height {
                let rowOffset = y * bytesPerRow
                for x in 0..<width {
                    let alpha = bytes[rowOffset + x * bytesPerPixel + 3]
                    if alpha > 8 {
                        minX = Swift.min(minX, x)
                        minY = Swift.min(minY, y)
                        maxX = Swift.max(maxX, x)
                        maxY = Swift.max(maxY, y)
                    }
                }
            }

            guard maxX >= minX, maxY >= minY else { return nil }
            let paddedMinX = Swift.max(minX - padding, 0)
            let paddedMinY = Swift.max(minY - padding, 0)
            let paddedMaxX = Swift.min(maxX + padding + 1, width)
            let paddedMaxY = Swift.min(maxY + padding + 1, height)
            return CGRect(x: paddedMinX,
                          y: paddedMinY,
                          width: paddedMaxX - paddedMinX,
                          height: paddedMaxY - paddedMinY)
        }

        guard let cropRect else { return image }
        return redraw(image, croppedTo: cropRect, colorSpace: colorSpace,
                      bitmapInfo: bitmapInfo) ?? image
    }

    private static func redraw(_ image: CGImage,
                               croppedTo cropRect: CGRect,
                               colorSpace: CGColorSpace,
                               bitmapInfo: UInt32) -> CGImage? {
        let cropWidth = Int(cropRect.width.rounded(.up))
        let cropHeight = Int(cropRect.height.rounded(.up))
        guard cropWidth > 0, cropHeight > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = cropWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * cropHeight)
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: cropWidth,
                                          height: cropHeight,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return nil
            }

            context.clear(CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight))
            context.translateBy(x: -cropRect.minX, y: -cropRect.minY)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context.makeImage()
        }
    }
}

private struct MonaCalendarWidgetView: View {
    let entry: MonaCalendarWidgetEntry

    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var body: some View {
        ZStack {
            switch entry.backgroundStyle {
            case .transparent, .border:
                Color.clear
            case .black:
                Color.black
            }

            calendarImage
        }
        .overlay {
            if entry.backgroundStyle == .border {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
                    .padding(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetAccentable(false)
        .containerBackground(for: .widget) {
            switch entry.backgroundStyle {
            case .transparent, .border:
                Color.clear
            case .black:
                Color.black
            }
        }
    }

    private var calendarImage: some View {
        GeometryReader { proxy in
            if let image = entry.image {
                let intrinsicSize = Self.intrinsicSize(of: image)
                let scale = Self.fitScale(for: intrinsicSize, in: proxy.size)
                Image(decorative: image, scale: 2, orientation: .up)
                    .widgetAccentedRenderingMode(.fullColor)
                    .widgetAccentable(false)
                    .frame(width: intrinsicSize.width, height: intrinsicSize.height)
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                fallback
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var fallback: some View {
        VStack(spacing: 4) {
            Text("\(entry.content.month)/\(entry.content.day)")
                .font(.system(size: 38, weight: .black, design: .rounded))
            Text(entry.content.weather.label)
                .font(.caption)
                .foregroundStyle(entry.backgroundStyle == .black ? .white.opacity(0.72) : .secondary)
        }
        .foregroundStyle(entry.backgroundStyle == .black ? .white : .primary)
    }

    private var borderColor: Color {
        widgetRenderingMode == .fullColor ? .primary.opacity(0.36) : .white.opacity(0.56)
    }

    private static func intrinsicSize(of image: CGImage) -> CGSize {
        CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
    }

    private static func fitScale(for intrinsicSize: CGSize, in containerSize: CGSize) -> CGFloat {
        let horizontalInset: CGFloat = 14
        let verticalInset: CGFloat = 14
        let availableWidth = Swift.max(containerSize.width - horizontalInset * 2, 1)
        let availableHeight = Swift.max(containerSize.height - verticalInset * 2, 1)
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else { return 1 }
        return Swift.min(availableWidth / intrinsicSize.width,
                         availableHeight / intrinsicSize.height)
    }
}

@main
struct MonaCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonaCalendarWidget()
        MonaCalendarWidgetBlack()
        MonaCalendarWidgetBorder()
    }
}

private struct MonaCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MonaCalendarWidgetConstants.kind,
                            provider: MonaCalendarWidgetProvider(backgroundStyle: .transparent)) { entry in
            MonaCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Mona Calendar Widget")
        .description("透明背景。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

private struct MonaCalendarWidgetBlack: Widget {
    private let kind = "\(MonaCalendarWidgetConstants.kind).black"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind,
                            provider: MonaCalendarWidgetProvider(backgroundStyle: .black)) { entry in
            MonaCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Mona Calendar Widget - Black")
        .description("全黑背景。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

private struct MonaCalendarWidgetBorder: Widget {
    private let kind = "\(MonaCalendarWidgetConstants.kind).border"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind,
                            provider: MonaCalendarWidgetProvider(backgroundStyle: .border)) { entry in
            MonaCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Mona Calendar Widget - Border")
        .description("只有边框。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
