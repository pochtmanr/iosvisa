import Foundation
import Supabase

/// Single shared Supabase client for the whole app. Uses the PUBLIC anon key;
/// every read/write is gated by Postgres Row Level Security tied to the
/// authenticated user's JWT — exactly the boundary the web client relies on.
///
/// supabase-swift persists the session in the Keychain automatically and
/// refreshes the JWT in the background.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )
}
