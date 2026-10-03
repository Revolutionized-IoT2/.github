# M2. Standardize on System.Text.Json and type the persistence layer

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Problem.** `Utils/Json.cs` serializes with Newtonsoft (`Serialize` ×26 call sites,
`SerializeIgnoreNulls` ×10, `Deserialize` ×7, `ToDictionary` ×6, plus `GetValue`/`FindValue`/
`SetValue` path helpers on `JToken`). `ValueModel` and ASP.NET Core use System.Text.Json, the
Orchestrator needs a `JObjectConverter` shim to bridge the two, and it registers three naming-policy
variants (default, `pascal`, `lower`). Persistence stores `dynamic` objects
(`StoredObjectService._objects: Dictionary<string, List<dynamic>>`, `(obj as dynamic).Id`), and
`StoredObjectEventHandler` passes `dynamic`. `TypeNameHandling.Auto` is still used for stored
configuration (now restricted by `RIoT2SerializationBinder`), but current stored files carry no
`$type` metadata.

## Steps

1. **Golden-file tests first.** Serialize every contract type (`Report`, `Command`,
   `NodeDeviceConfiguration`, `DashboardConfiguration`, `Variable`, `NodeOnlineMessage`,
   `ConfigurationCommand`, `ValueModel` of each `ValueType`) with the current code and commit the
   JSON. Also commit real `StoredObjects` samples with secrets scrubbed. These golden files become
   the definition of the wire format.
2. **One System.Text.Json setup.** Add a single `RIoT2JsonOptions` (camelCase, ignore nulls,
   `ValueModelConverter`, enum handling matching today's numbers) and a source-generated
   `JsonSerializerContext` for the contract types in `Contracts`.
3. Re-implement `Json.Serialize`/`Deserialize`/`SerializeIgnoreNulls`/`ToDictionary`/path helpers
   on System.Text.Json (`JsonNode` replaces `JToken`) behind the same method signatures. Switch
   callers repo by repo until the golden tests pass, and mark the Newtonsoft-only entry points
   (`DeserializeAutoTypeNameHandling`, `DeserializePascal`, `ToDictionary(JObject)`) `[Obsolete]`.
4. **Typed persistence.** Replace `dynamic` in `StoredObjectService` with an `IStoredObject`
   interface (`string Id { get; set; }`) implemented by the stored model types, a generic
   `IObjectStore<T> where T : IStoredObject`, and a typed `StoredObjectChanged<T>` event. Drop
   `TypeNameHandling`, which works because current stored configurations carry no `$type`. Add a
   one-time loader that ignores or archives the legacy `Rule` files that still contain
   `ExpandoObject`.
5. Remove the `JObjectConverter` shim and the `pascal`/`lower` naming variants
   (`CustomJsonSettings/Formatters.cs`, selected by a `json-naming-policy` request header). None of
   the UI, Elsa, Mobile or firmware sends that header, so the only possible users are external
   scripts. Log a deprecation warning when the header is seen for one release, then delete it.
6. Remove the Newtonsoft dependency from Core. Plugins that need it reference it themselves.

**Risk.** Subtle format differences: number and enum formats, null handling, dictionary key casing.
The golden files from step 1 catch them.

**Done when.** `RIoT2.Core.Contracts` has no Newtonsoft reference, there's no `dynamic` in
persistence, and the golden-file tests pass in Core, the Orchestrator and Elsa.
