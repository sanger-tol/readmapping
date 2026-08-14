class HeaderUtils {
    static List sanitizeHeader(def text) {
        def lines = text?.getClass()?.isArray()
            ? text.toList()
            : (text instanceof Collection ? text : (text?.toString()?.readLines() ?: []))
        lines.collect { line ->
            line.toString()
                // SQ UR: keep basename only
                .replaceAll(/\bUR:\/(?:[^\/\s]+\/)*([^\/\s]+)/, 'UR:$1')
                // Absolute paths anywhere (CL args, temp dirs, etc.)
                .replaceAll(/\/(?:[^\/\t ]+\/)+([^\/\t ]+)/, '$1')
                // Thread counts that track CI cpus
                .replaceAll(/\s-(?:t|@)\s*\d+/, ' -t N')
                .replaceAll(/\s--threads\s+\d+/, ' --threads N')
        }
    }
}