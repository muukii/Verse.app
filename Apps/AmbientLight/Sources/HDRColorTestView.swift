import SwiftUI

/// HDR Color Test View for iOS 26.0+
/// Demonstrates headroom(_:) and exposureAdjust(_:) APIs
@available(iOS 26.0, macOS 26.0, *)
struct HDRColorTestView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 32) {
        // MARK: - SDR vs HDR Comparison
        sdrVsHdrSection

        Divider()

        // MARK: - Headroom Values Comparison
        headroomSection

        Divider()

        // MARK: - Exposure Adjust Effect
        exposureAdjustSection
      }
      .padding()
    }
    .navigationTitle("HDR Color Test")
  }

  // MARK: - SDR vs HDR Comparison Section

  private var sdrVsHdrSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("SDR vs HDR Comparison")
        .font(.headline)

      Text("Left: SDR / Right: HDR (headroom: 4)")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 12) {
        colorComparisonRow(
          label: "Yellow",
          sdrColor: .yellow,
          hdrColor: Color(.displayP3, red: 1.0, green: 1.0, blue: 0).headroom(4)
        )

        colorComparisonRow(
          label: "Red",
          sdrColor: .red,
          hdrColor: Color(.displayP3, red: 1.0, green: 0, blue: 0).headroom(4)
        )

        colorComparisonRow(
          label: "Green",
          sdrColor: .green,
          hdrColor: Color(.displayP3, red: 0, green: 1.0, blue: 0).headroom(4)
        )

        colorComparisonRow(
          label: "Blue",
          sdrColor: .blue,
          hdrColor: Color(.displayP3, red: 0, green: 0, blue: 1.0).headroom(4)
        )

        colorComparisonRow(
          label: "HDR Yellow",
          sdrColor: .yellow,
          hdrColor: Color(.sRGB, red: 1.83, green: 1.47, blue: 0).headroom(4)
        )
      }
    }
  }

  private func colorComparisonRow(
    label: String,
    sdrColor: Color,
    hdrColor: Color
  ) -> some View {
    HStack(spacing: 16) {
      Text(label)
        .frame(width: 100, alignment: .leading)

      VStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(sdrColor)
          .frame(height: 50)
        Text("SDR")
          .font(.caption2)
      }

      VStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(hdrColor)
          .frame(height: 50)
        Text("HDR")
          .font(.caption2)
      }
    }
  }

  // MARK: - Headroom Section

  private var headroomSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Headroom Values")
        .font(.headline)

      Text("Same HDR color with different headroom values")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 12) {
        // Yellow with different headrooms
        HStack(spacing: 8) {
          Text("Yellow")
            .font(.caption)
            .frame(width: 60, alignment: .leading)

          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.sRGB, red: 1.83, green: 1.47, blue: 0).headroom(1))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.sRGB, red: 1.83, green: 1.47, blue: 0).headroom(2))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.sRGB, red: 1.83, green: 1.47, blue: 0).headroom(4))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.sRGB, red: 1.83, green: 1.47, blue: 0).headroom(8))
            .frame(height: 40)
        }

        // Red with different headrooms
        HStack(spacing: 8) {
          Text("Red")
            .font(.caption)
            .frame(width: 60, alignment: .leading)

          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.5, green: 0, blue: 0).headroom(1))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.5, green: 0, blue: 0).headroom(2))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.5, green: 0, blue: 0).headroom(4))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.5, green: 0, blue: 0).headroom(8))
            .frame(height: 40)
        }

        // White with different headrooms
        HStack(spacing: 8) {
          Text("White")
            .font(.caption)
            .frame(width: 60, alignment: .leading)

          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0).headroom(1))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0).headroom(2))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0).headroom(4))
            .frame(height: 40)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0).headroom(8))
            .frame(height: 40)
        }
      }

      // Headroom value labels
      HStack(spacing: 8) {
        Text("")
          .frame(width: 60)
        Text("1")
          .font(.caption2)
          .frame(maxWidth: .infinity)
        Text("2")
          .font(.caption2)
          .frame(maxWidth: .infinity)
        Text("4")
          .font(.caption2)
          .frame(maxWidth: .infinity)
        Text("8")
          .font(.caption2)
          .frame(maxWidth: .infinity)
      }
      .foregroundStyle(.secondary)
    }
  }

  // MARK: - Exposure Adjust Section

  private var exposureAdjustSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Exposure Adjust")
        .font(.headline)

      Text("System colors with exposure adjustment (-2 to +4)")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 12) {
        exposureRow(label: "Yellow", baseColor: .yellow)
        exposureRow(label: "Red", baseColor: .red)
        exposureRow(label: "Green", baseColor: .green)
        exposureRow(label: "Blue", baseColor: .blue)
        exposureRow(label: "Gray", baseColor: .gray)
      }

      // Exposure value labels
      HStack(spacing: 4) {
        Text("")
          .frame(width: 60)
        ForEach([-2, -1, 0, 1, 2, 3, 4], id: \.self) { value in
          Text(value >= 0 ? "+\(value)" : "\(value)")
            .font(.caption2)
            .frame(maxWidth: .infinity)
        }
      }
      .foregroundStyle(.secondary)
    }
  }

  private func exposureRow(label: String, baseColor: Color) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.caption)
        .frame(width: 60, alignment: .leading)

      RoundedRectangle(cornerRadius: 4)
        .fill(baseColor.exposureAdjust(-2))
        .frame(height: 35)
      RoundedRectangle(cornerRadius: 4)
        .fill(baseColor.exposureAdjust(-1))
        .frame(height: 35)
      RoundedRectangle(cornerRadius: 4)
        .fill(baseColor.exposureAdjust(0))
        .frame(height: 35)
      RoundedRectangle(cornerRadius: 4)
        .fill(baseColor.exposureAdjust(1))
        .frame(height: 35)
      RoundedRectangle(cornerRadius: 4)
        .fill(baseColor.exposureAdjust(2))
        .frame(height: 35)
      RoundedRectangle(cornerRadius: 4)
        .fill(baseColor.exposureAdjust(3))
        .frame(height: 35)
      RoundedRectangle(cornerRadius: 4)
        .fill(baseColor.exposureAdjust(4))
        .frame(height: 35)
    }
  }
}

// MARK: - Preview

@available(iOS 26.0, macOS 26.0, *)
#Preview("HDR Color Test") {
  NavigationStack {
    HDRColorTestView()
  }
}

@available(iOS 26.0, macOS 26.0, *)
#Preview("HDR Color Test (Dark)") {
  NavigationStack {
    HDRColorTestView()
  }
  .preferredColorScheme(.dark)
}
