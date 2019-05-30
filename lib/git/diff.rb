# frozen_string_literal: true

module Git
  # object that holds the last X commits on given branch
  class Diff
    include Enumerable

    def initialize(base, from = nil, to = nil)
      @base = base
      @from = from&.to_s
      @to = to&.to_s

      @path = nil
      @full_diff = nil
      @full_diff_files = nil
      @stats = nil
    end
    attr_reader :from, :to

    def name_status
      cache_name_status
    end

    def path(path)
      @path = path
      self
    end

    def size
      cache_stats
      @stats[:total][:files]
    end

    def lines
      cache_stats
      @stats[:total][:lines]
    end

    def deletions
      cache_stats
      @stats[:total][:deletions]
    end

    def insertions
      cache_stats
      @stats[:total][:insertions]
    end

    def stats
      cache_stats
      @stats
    end

    # if file is provided and is writable, it will write the patch into the file
    def patch(_file = nil)
      cache_full
      @full_diff
    end
    alias to_s patch

    # enumerable methods

    def [](key)
      process_full
      @full_diff_files.assoc(key)[1]
    end

    def each(&block) # :yields: each Git::DiffFile in turn
      process_full
      @full_diff_files.map { |file| file[1] }.each(&block)
    end

    class DiffFile
      attr_accessor :patch, :path, :mode, :src, :dst, :type
      @base = nil

      def initialize(base, hash)
        @base = base
        @patch = hash[:patch]
        @path = hash[:path]
        @mode = hash[:mode]
        @src = hash[:src]
        @dst = hash[:dst]
        @type = hash[:type]
        @binary = hash[:binary]
      end

      def binary?
        @binary.nil?
      end

      def blob(type = :dst)
        return @base.object(@src) if type == :src && @src != '0000000'
        return @base.object(@dst) if type != :src && @dst != '0000000'
      end
    end

    private

    def cache_full
      @full_diff ||= @base.lib.diff_full(@from, @to, path_limiter: @path)
    end

    def process_full
      return if @full_diff_files

      cache_full
      @full_diff_files = process_full_diff
    end

    def cache_stats
      @stats ||= @base.lib.diff_stats(@from, @to, path_limiter: @path)
    end

    def cache_name_status
      @name_status ||= @base.lib.diff_name_status(@from, @to, path: @path)
    end

    # break up @diff_full
    def process_full_diff
      defaults = {
        mode: '',
        src: '',
        dst: '',
        type: 'modified'
      }
      final = {}
      current_file = nil
      full_diff_utf8_encoded = if @full_diff.encoding.name != 'UTF-8'
                                 @full_diff.encode('UTF-8', 'binary', invalid: :replace, undef: :replace)
                               else
                                 @full_diff
                               end
      full_diff_utf8_encoded.split("\n").each do |line|
        if (m = %r{^diff --git a\/(.*?) b\/(.*?)}.match(line))
          current_file = m[1]
          final[current_file] = defaults.merge(patch: line, path: current_file)
        else
          if (m = /^index (.......)\.\.(.......)( ......)*/.match(line))
            final[current_file][:src] = m[1]
            final[current_file][:dst] = m[2]
            final[current_file][:mode] = m[3].strip if m[3]
          end
          if (m = /^([[:alpha:]]*?) file mode (......)/.match(line))
            final[current_file][:type] = m[1]
            final[current_file][:mode] = m[2]
          end
          final[current_file][:binary] = true if /^Binary files / =~ line
          final[current_file][:patch] << "\n" + line
        end
      end
      final.map { |e| [e[0], DiffFile.new(@base, e[1])] }
    end
  end
end
