unit SimpleAttributes;

interface

uses
  System.RTTI, System.Variants, System.Classes, SimpleTypes;

type
  Tabela = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(aName: string);
    property Name: string read FName;
  end;

  Campo = class(TCustomAttribute)
  private
    FName: string;
  public
    Constructor Create(aName: string);
    property Name: string read FName;
  end;

  PK = class(TCustomAttribute)
  end;

  FK = class(TCustomAttribute)
  end;

  NotNull = class(TCustomAttribute)
  end;

  NotZero = class(TCustomAttribute)
  end;

  Ignore = class(TCustomAttribute)
  end;

  AutoInc = class(TCustomAttribute)
  end;

  NumberOnly = class(TCustomAttribute)
  end;

  Automapping = class(TCustomAttribute)
  end;

  Bind = class(TCustomAttribute)
  private
    FField: String;
    procedure SetField(const Value: String);
  public
    constructor Create (aField : String);
    property Field : String read FField write SetField;
  end;

  Display = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const aName: string);
    property Name: string read FName write FName;
  end;

  Format = class(TCustomAttribute)
  private
    FMaxSize: integer;
    FPrecision: integer;
    FMask: string;
    FMinSize: integer;
  public
    property MaxSize: integer read FMaxSize write FMaxSize;
    property MinSize: integer read FMinSize write FMinSize;
    property Precision: integer read FPrecision write FPrecision;
    property Mask: string read FMask write FMask;
    function GetNumericMask: string;
    constructor Create(const aSize: Integer; const aPrecision: integer = 0); overload;
    constructor Create(const aMask: string); overload;
    constructor Create(const aRange: array of Integer); overload;
  end;

  Relationship = class abstract(TCustomAttribute)
  private
    FEntityName: string;
    FForeignKey: string;
  public
    constructor Create(const aEntityName: string); overload;
    constructor Create(const aEntityName, aForeignKey: string); overload;
    property EntityName: string read FEntityName write FEntityName;
    property ForeignKey: string read FForeignKey write FForeignKey;
  end;

  HasOne = class(Relationship)
  end;

  BelongsTo = class(Relationship)
  end;
  
  HasMany = class(Relationship)
  end;

  BelongsToMany = class(Relationship)
  end;

  SoftDelete = class(TCustomAttribute)
  private
    FFieldName: string;
  public
    constructor Create(const aFieldName: string);
    property FieldName: string read FFieldName;
  end;

  Enumerator = class(TCustomAttribute)
  private
    FTipo: string;
  public
    Constructor Create(aTipo: string);
    property Tipo: string read FTipo;
  end;

  Email = class(TCustomAttribute)
  end;

  Uuid = class(TCustomAttribute)
  end;

  MinValue = class(TCustomAttribute)
  private
    FValue: Double;
  public
    constructor Create(aValue: Double);
    property Value: Double read FValue;
  end;

  MaxValue = class(TCustomAttribute)
  private
    FValue: Double;
  public
    constructor Create(aValue: Double);
    property Value: Double read FValue;
  end;

  Regex = class(TCustomAttribute)
  private
    FPattern: string;
    FMessage: string;
  public
    constructor Create(const aPattern: string; const aMessage: string = '');
    property Pattern: string read FPattern;
    property Message: string read FMessage;
  end;

  IgnoreUpdate = class(TCustomAttribute)
  end;

  IgnoreJSON = class(TCustomAttribute)
  end;

  JSONBase64 = class(TCustomAttribute)
  end;

  CreatedAt = class(TCustomAttribute)
  end;

  UpdatedAt = class(TCustomAttribute)
  end;

  CascadeDelete = class(TCustomAttribute)
  end;

  CPF = class(TCustomAttribute)
  end;

  CNPJ = class(TCustomAttribute)
  end;

  /// AI-generated content: LLM generates value based on a prompt template.
  /// Template can reference other property values with {PropertyName}.
  AIGenerated = class(TCustomAttribute)
  private
    FPromptTemplate: String;
  public
    constructor Create(const aPromptTemplate: String);
    property PromptTemplate: String read FPromptTemplate;
  end;

  /// AI summarization: LLM creates a summary of the source property value.
  AISummarize = class(TCustomAttribute)
  private
    FSourceProperty: String;
    FMaxLength: Integer;
  public
    constructor Create(const aSourceProperty: String; aMaxLength: Integer = 0);
    property SourceProperty: String read FSourceProperty;
    property MaxLength: Integer read FMaxLength;
  end;

  /// AI translation: LLM translates the source property to target language.
  AITranslate = class(TCustomAttribute)
  private
    FSourceProperty: String;
    FTargetLanguage: String;
  public
    constructor Create(const aSourceProperty: String; const aTargetLanguage: String);
    property SourceProperty: String read FSourceProperty;
    property TargetLanguage: String read FTargetLanguage;
  end;

  /// AI classification: LLM classifies the source property into one of the given categories.
  AIClassify = class(TCustomAttribute)
  private
    FSourceProperty: String;
    FCategories: String;
  public
    constructor Create(const aSourceProperty: String; const aCategories: String);
    property SourceProperty: String read FSourceProperty;
    property Categories: String read FCategories;
  end;

  /// AI validation: LLM validates a property value against a rule.
  /// Raises exception if validation fails.
  AIValidate = class(TCustomAttribute)
  private
    FRule: String;
    FErrorMessage: String;
  public
    constructor Create(const aRule: String; const aErrorMessage: String = '');
    property Rule: String read FRule;
    property ErrorMessage: String read FErrorMessage;
  end;

  Rule = class(TCustomAttribute)
  private
    FExpression: String;
    FAction: TRuleAction;
    FMessage: String;
  public
    constructor Create(const aExpression: String; aAction: TRuleAction; const aMessage: String = '');
    property Expression: String read FExpression;
    property Action: TRuleAction read FAction;
    property &Message: String read FMessage;
  end;

  AIRule = class(TCustomAttribute)
  private
    FDescription: String;
    FAction: TRuleAction;
  public
    constructor Create(const aDescription: String; aAction: TRuleAction);
    property Description: String read FDescription;
    property Action: TRuleAction read FAction;
  end;

implementation


{ Bind }

constructor Bind.Create(aField: String);
begin
  FField := aField;
end;

procedure Bind.SetField(const Value: String);
begin
  FField := Value;
end;

{ Tabela }

constructor Tabela.Create(aName: string);
begin
  FName := aName;
end;

{ Campo }

constructor Campo.Create(aName: string);
begin
  FName := aName;
end;

{ Display }

constructor Display.Create(const aName: string);
begin
  FName := aName;
end;

{ Formato }

constructor Format.Create(const aSize, aPrecision: integer);
begin
  FMaxSize := aSize;
  FPrecision := aPrecision;
end;

constructor Format.Create(const aMask: string);
begin
  FMask := aMask;
end;

constructor Format.Create(const aRange: array of Integer);
begin
  FMinSize := aRange[0];
  FMaxSize := aRange[High(aRange)];
end;

function Format.GetNumericMask: string;
var
  sTamanho, sPrecisao: string;
begin
  sTamanho := StringOfChar('0', FMaxSize - FPrecision);
  sPrecisao := StringOfChar('0', FPrecision);

  Result := sTamanho + '.' + sPrecisao;
end;

{ Relationship }

constructor Relationship.Create(const aEntityName: string);
begin
  FEntityName := aEntityName;
  FForeignKey := '';
end;

constructor Relationship.Create(const aEntityName, aForeignKey: string);
begin
  FEntityName := aEntityName;
  FForeignKey := aForeignKey;
end;

{ SoftDelete }

constructor SoftDelete.Create(const aFieldName: string);
begin
  FFieldName := aFieldName;
end;

{ Enumerator }

constructor Enumerator.Create(aTipo: string);
begin
  FTipo := aTipo;
end;

{ MinValue }

constructor MinValue.Create(aValue: Double);
begin
  FValue := aValue;
end;

{ MaxValue }

constructor MaxValue.Create(aValue: Double);
begin
  FValue := aValue;
end;

{ Regex }

constructor Regex.Create(const aPattern: string; const aMessage: string = '');
begin
  FPattern := aPattern;
  FMessage := aMessage;
end;

{ AIGenerated }

constructor AIGenerated.Create(const aPromptTemplate: String);
begin
  FPromptTemplate := aPromptTemplate;
end;

{ AISummarize }

constructor AISummarize.Create(const aSourceProperty: String; aMaxLength: Integer);
begin
  FSourceProperty := aSourceProperty;
  FMaxLength := aMaxLength;
end;

{ AITranslate }

constructor AITranslate.Create(const aSourceProperty: String; const aTargetLanguage: String);
begin
  FSourceProperty := aSourceProperty;
  FTargetLanguage := aTargetLanguage;
end;

{ AIClassify }

constructor AIClassify.Create(const aSourceProperty: String; const aCategories: String);
begin
  FSourceProperty := aSourceProperty;
  FCategories := aCategories;
end;

{ AIValidate }

constructor AIValidate.Create(const aRule: String; const aErrorMessage: String);
begin
  FRule := aRule;
  FErrorMessage := aErrorMessage;
end;

{ Rule }

constructor Rule.Create(const aExpression: String; aAction: TRuleAction; const aMessage: String);
begin
  FExpression := aExpression;
  FAction := aAction;
  FMessage := aMessage;
end;

{ AIRule }

constructor AIRule.Create(const aDescription: String; aAction: TRuleAction);
begin
  FDescription := aDescription;
  FAction := aAction;
end;

end.
