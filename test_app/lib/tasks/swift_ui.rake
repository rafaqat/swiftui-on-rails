# frozen_string_literal: true

namespace :swift_ui do
  desc "Lint SwiftUI Rails files. FILE=path for one file; omit to sweep the corpus. [FORMAT=json] [SEVERITY=error]"
  task lint: :environment do
    files = if ENV["FILE"].present?
      [ ENV["FILE"] ]
    else
      [
        "app/components/**/*_component.rb",
        "test/components/stories/*_stories.rb"
      ].flat_map { |glob| Dir.glob(Rails.root.join(glob)) }
                  .map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }.sort
    end

    minimum = ENV["SEVERITY"].presence
    all_findings = files.to_h { |file| [ file, SwiftUi::Lint.call(file) ] }
    all_findings.transform_values! { |diags| diags.reject { |d| d.severity == "info" } } if minimum
    all_findings.transform_values! { |diags| diags.select { |d| d.severity == "error" } } if minimum == "error"

    if ENV["FORMAT"] == "json"
      puts JSON.pretty_generate(all_findings.transform_values { |diags| diags.map(&:to_h) }.reject { |_, v| v.empty? })
    else
      clean = 0
      all_findings.each do |file, diagnostics|
        if diagnostics.empty?
          clean += 1
          next
        end
        diagnostics.each do |diagnostic|
          location = diagnostic.line ? ":#{diagnostic.line}#{diagnostic.column ? ":#{diagnostic.column}" : ''}" : ""
          puts "#{diagnostic.severity.upcase} [#{diagnostic.code}] #{file}#{location} — #{diagnostic.message}"
          puts "  hint: #{diagnostic.hint}" if diagnostic.hint
        end
      end
      puts "#{files.length} files linted: #{clean} clean, #{files.length - clean} with findings"
    end

    exit(1) if all_findings.values.flatten.any? { |diagnostic| diagnostic.severity == "error" }
  end

  namespace :language do
    desc "Print the machine-readable playground language manifest. COMPACT=1 emits the generation profile"
    task manifest: :environment do
      manifest = if ENV["COMPACT"] == "1"
        Showcase::Playground::LanguageCatalog.for_generation
      else
        Showcase::Playground::LanguageCatalog.to_h
      end

      puts JSON.pretty_generate(manifest)
    end
  end

  namespace :playground do
    desc "Canonicalize playground DSL. SOURCE=path|- (stdin); WRITE=1 replaces the source file"
    task format: :environment do
      source_path = ENV["SOURCE"].presence || "-"
      source = source_path == "-" ? $stdin.read : File.read(source_path)
      result = Showcase::Playground::SourceFormatter.call(source)

      unless result.success?
        warn JSON.pretty_generate(ok: false, diagnostics: result.diagnostics)
        exit(1)
      end

      if ENV["WRITE"] == "1"
        abort "WRITE=1 requires SOURCE to name a file" if source_path == "-"

        File.write(source_path, result.source)
        puts "Formatted #{source_path}"
      else
        $stdout.write(result.source)
      end
    end
  end

  namespace :artifact do
    desc "Verify a durable playground artifact. ARTIFACT=path|- (stdin)"
    task verify: :environment do
      artifact_path = ENV["ARTIFACT"].presence || "-"
      artifact = artifact_path == "-" ? $stdin.read : File.read(artifact_path)
      result = Showcase::Playground::ArtifactVerifier.call(
        artifact,
        view_context: ApplicationController.new.view_context
      )

      puts JSON.pretty_generate(result.as_json)
      exit(1) unless result.success?
    end
  end

  namespace :reliability do
    desc "Run the fixed playground generation reliability corpus and print its JSON report"
    task report: :environment do
      report = Showcase::Playground::ReliabilityEvaluator.call(
        view_context: ApplicationController.new.view_context
      )

      puts JSON.pretty_generate(report.as_json)
      exit(1) unless report.success?
    end
  end

  namespace :tokens do
    desc "Count the fixed React Rails versus SwiftUI Rails reference corpus and print its JSON report"
    task report: :environment do
      report = Showcase::TokenBenchmark::Evaluator.call

      puts JSON.pretty_generate(report.as_json)
      exit(1) unless report.success?
    end
  end
end

namespace :playground do
  desc "Compile playground DSL source to JSON diagnostics. SOURCE=path|- (stdin) [DATA=path]"
  task compile: :environment do
    source = if ENV["SOURCE"].blank? || ENV["SOURCE"] == "-"
      $stdin.read
    else
      File.read(ENV["SOURCE"])
    end
    data_json = ENV["DATA"].present? ? File.read(ENV["DATA"]) : "{}"

    result = Showcase::Playground::Runner.call(
      source: source,
      data_json: data_json,
      view_context: ApplicationController.new.view_context
    )

    puts JSON.pretty_generate(result.as_json)
    exit(result.success? ? 0 : 1)
  end
end
