class PhoneMirror < Formula
  desc "Mirror Android devices and transfer files from macOS"
  homepage "https://github.com/2021Dt/phone-mirror"
  url "https://github.com/2021Dt/phone-mirror.git", tag: "v0.2.0"

  depends_on :macos
  depends_on "scrcpy"

  def install
    system ENV.cc, "-Os", "-fobjc-arc", "phone-hotkeys.m",
           "-framework", "AppKit", "-framework", "Carbon", "-o", "phone-hotkeys"
    libexec.install "phone.zsh", "phone-transfer.zsh", "phone-picker.js", "phone-hotkeys"
    (libexec/"phone.zsh").chmod 0755
    bin.install_symlink libexec/"phone.zsh" => "phone"
  end

  def caveats
    <<~EOS
      If adb is missing, install it with:
        brew install --cask android-platform-tools
    EOS
  end

  test do
    assert_match "phone get", shell_output("#{bin}/phone -h")
    assert_predicate libexec/"phone-hotkeys", :executable?
    assert_path_exists libexec/"phone-picker.js"
    assert_path_exists libexec/"phone-transfer.zsh"
  end
end
