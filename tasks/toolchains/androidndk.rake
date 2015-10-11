
class MRuby::Toolchain::AndroidNDK
  DEFAULT_ARCH = 'armeabi'
  DEFAULT_PLATFORM = 'android-14'
  DEFAULT_TOOLCHAIN = :gcc
  DEFAULT_NDK_HOMES = %w{
    /usr/local/opt/android-ndk
  }
  TOOLCHAINS = [:gcc, :clang]
  ARCHITECTURES = %w{
    armeabi armeabi-v7a arm64-v8a
    mips mips64
    x86 x86_64
  }

  class AndroidNDKHomeNotFound < StandardError
    def message
        <<-EOM
Couldn't find Android NDK Home.
Set ANDROID_NDK_HOME environment variable or set :ndk_home parameter
        EOM
    end
  end

  attr_reader :params

  def initialize(params)
    @params = params
  end

  def home_path
    @home_path ||= Pathname(
      params[:ndk_home] ||
        ENV['ANDROID_NDK_HOME'] ||
        DEFAULT_NDK_HOMES.find{ |path| File.directory?(path) } ||
        raise(AndroidNDKHomeNotFound)
    )
  end

  def arch
    params.fetch(:arch){ DEFAULT_ARCH }
  end

  def platform
    params.fetch(:platform){ DEFAULT_PLATFORM }
  end

  def toolchain
    params.fetch(:toolchain){ DEFAULT_TOOLCHAIN }
  end

  def toolchain_version
    params.fetch(:toolchain_version) do
      test = case toolchain
      when :gcc
        'arm-linux-androideabi-*'
      when :clang
        'llvm-*'
      end

      Dir[home_path.join('toolchains',test)].map{|t| t.match(/-(\d+\.\d+)$/); $1.to_f }.max
    end
  end

  def toolchain_path
    prefix = case toolchain
             when :clang then 'llvm-'
             when :gcc
               case arch
               when /arm/  then 'arm-linux-androideabi-'
               when /x86/  then 'x86-'
               when /mips/ then 'mipsel-linux-android-'
               end
             end
    home_path.join('toolchains', prefix + toolchain_version.to_s, 'prebuilt', host_platform)
  end

  def sysroot
    path = case arch
           when /arm/  then 'arch-arm'
           when /x86/  then 'arch-x86'
           when /mips/ then 'arch-mips'
           end

    home_path.join('platforms', platform, path).to_s
  end

  def bin(command)
    command = command.to_s

    if toolchain == :gcc
      command = case arch
                when /arm/  then 'arm-linux-androideabi-'
                when /x86/  then 'i686-linux-android-'
                when /mips/ then 'mipsel-linux-android-'
                end + command
    end

    toolchain_path.join('bin',command).to_s
  end

  def cc
    case toolchain
    when :gcc   then bin(:gcc)
    when :clang then bin(:clang)
    end
  end

  def cflags
    flags = []

    case toolchain
    when :gcc
      flags += %W(-ffunction-sections -funwind-tables -fstack-protector)
      flags += %W(-D__android__ -mandroid --sysroot="#{sysroot}")
      case arch
      when 'armeabi-v7a'
        flags += %W(-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16)
      when /arm/
        flags += %W(-march=armv5te -mtune=xscale -msoft-float)
      when /mips/
        flags += %W(-fpic -fno-strict-aliasing -finline-functions -fmessage-length=0 -fno-inline-functions-called-once -fgcse-after-reload -frerun-cse-after-loop -frename-registers)
      end
    when :clang
    end

    flags
  end

  def ld
    cc
  end

  def ldflags
    %W(-D__android__ -mandroid --sysroot="#{sysroot}")
  end

  def ar
    case toolchain
    when :gcc   then bin(:ar)
    when :clang then bin('llvm-ar')
    end
  end

  def host_platform
    case RUBY_PLATFORM
    when /cygwin|mswin|mingw|bccwin|wince|emx/i
      'windows'
    when /x86_64-darwin/i
      'darwin-x86_64'
    when /darwin/i
      'darwin-x86'
    when /x86_64-linux/i
      'linux-x86_64'
    when /linux/i
      'linux-x86'
    else
      raise NotImplementedError, "Unknown host platform (#{RUBY_PLATFORM})"
    end
  end
end

MRuby::Toolchain.new(:androidndk) do |conf, params|
  ndk = MRuby::Toolchain::AndroidNDK.new(params)

  toolchain ndk.toolchain

  [conf.cc, conf.cxx, conf.objc, conf.asm].each do |cc|
    cc.command = ndk.cc
    cc.flags = ndk.cflags
  end
  conf.linker.command = ndk.ld
  conf.linker.flags = ndk.ldflags
  conf.archiver.command = ndk.ar
end
