-- Criar enum para roles de usuários
CREATE TYPE public.app_role AS ENUM ('proprietario', 'cliente', 'corretor', 'gestor');

-- Criar tipo de enum para tipo de imóvel
CREATE TYPE public.property_type AS ENUM ('casa', 'apartamento', 'loja', 'terreno', 'escritorio');

-- Criar tipo de enum para status do imóvel
CREATE TYPE public.property_status AS ENUM ('disponivel', 'alugado', 'vendido', 'pendente');

-- Criar tipo de enum para tipo de transação
CREATE TYPE public.transaction_type AS ENUM ('venda', 'arrendamento', 'temporada');

-- Criar tabela de user_roles
CREATE TABLE public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role app_role NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    UNIQUE (user_id, role)
);

-- Habilitar RLS na tabela user_roles
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Criar função de segurança para verificar roles
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- Criar tabela de profiles
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone TEXT,
    provincia TEXT,
    municipio TEXT,
    bairro TEXT,
    bi_number TEXT,
    nif TEXT,
    bi_document_url TEXT,
    nif_document_url TEXT,
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Habilitar RLS na tabela profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Criar tabela de properties (imóveis)
CREATE TABLE public.properties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    property_type property_type NOT NULL,
    transaction_type transaction_type NOT NULL,
    status property_status DEFAULT 'disponivel' NOT NULL,
    price DECIMAL(15, 2) NOT NULL,
    provincia TEXT NOT NULL,
    municipio TEXT NOT NULL,
    bairro TEXT NOT NULL,
    address TEXT NOT NULL,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    bedrooms INTEGER,
    bathrooms INTEGER,
    area_total DECIMAL(10, 2),
    area_util DECIMAL(10, 2),
    has_garage BOOLEAN DEFAULT false,
    garage_spaces INTEGER DEFAULT 0,
    featured BOOLEAN DEFAULT false,
    views_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Habilitar RLS na tabela properties
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;

-- Criar índices para melhor performance
CREATE INDEX idx_properties_owner ON public.properties(owner_id);
CREATE INDEX idx_properties_status ON public.properties(status);
CREATE INDEX idx_properties_location ON public.properties(provincia, municipio, bairro);
CREATE INDEX idx_properties_type ON public.properties(property_type, transaction_type);

-- Criar tabela de property_images
CREATE TABLE public.property_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES public.properties(id) ON DELETE CASCADE NOT NULL,
    image_url TEXT NOT NULL,
    is_cover BOOLEAN DEFAULT false,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Habilitar RLS na tabela property_images
ALTER TABLE public.property_images ENABLE ROW LEVEL SECURITY;

-- Criar índice
CREATE INDEX idx_property_images_property ON public.property_images(property_id);

-- Criar tabela de property_visits (agendamentos)
CREATE TABLE public.property_visits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES public.properties(id) ON DELETE CASCADE NOT NULL,
    visitor_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    visit_date TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT DEFAULT 'pendente' CHECK (status IN ('pendente', 'confirmado', 'cancelado', 'realizado')),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Habilitar RLS na tabela property_visits
ALTER TABLE public.property_visits ENABLE ROW LEVEL SECURITY;

-- Criar índices
CREATE INDEX idx_property_visits_property ON public.property_visits(property_id);
CREATE INDEX idx_property_visits_visitor ON public.property_visits(visitor_id);

-- Criar tabela de reviews (avaliações)
CREATE TABLE public.reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES public.properties(id) ON DELETE CASCADE NOT NULL,
    reviewer_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5) NOT NULL,
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    UNIQUE (property_id, reviewer_id)
);

-- Habilitar RLS na tabela reviews
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- Criar índice
CREATE INDEX idx_reviews_property ON public.reviews(property_id);

-- Função para atualizar o campo updated_at automaticamente
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Criar triggers para updated_at
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_properties_updated_at
    BEFORE UPDATE ON public.properties
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_property_visits_updated_at
    BEFORE UPDATE ON public.property_visits
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_reviews_updated_at
    BEFORE UPDATE ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- Trigger para criar profile automaticamente ao criar usuário
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, phone)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
        COALESCE(NEW.raw_user_meta_data->>'phone', '')
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- RLS POLICIES
-- ============================================

-- Policies para user_roles
CREATE POLICY "Usuários podem ver seus próprios roles"
    ON public.user_roles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Apenas admins podem inserir roles"
    ON public.user_roles FOR INSERT
    WITH CHECK (public.has_role(auth.uid(), 'gestor'));

-- Policies para profiles
CREATE POLICY "Perfis são visíveis por todos usuários autenticados"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Usuários podem atualizar seu próprio perfil"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Usuários podem inserir seu próprio perfil"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Policies para properties
CREATE POLICY "Imóveis disponíveis são visíveis por todos"
    ON public.properties FOR SELECT
    USING (status = 'disponivel' OR owner_id = auth.uid() OR public.has_role(auth.uid(), 'gestor'));

CREATE POLICY "Proprietários podem criar imóveis"
    ON public.properties FOR INSERT
    WITH CHECK (
        auth.uid() = owner_id AND
        (public.has_role(auth.uid(), 'proprietario') OR public.has_role(auth.uid(), 'corretor'))
    );

CREATE POLICY "Proprietários podem atualizar seus imóveis"
    ON public.properties FOR UPDATE
    USING (auth.uid() = owner_id OR public.has_role(auth.uid(), 'gestor'));

CREATE POLICY "Proprietários podem deletar seus imóveis"
    ON public.properties FOR DELETE
    USING (auth.uid() = owner_id OR public.has_role(auth.uid(), 'gestor'));

-- Policies para property_images
CREATE POLICY "Imagens são visíveis para todos"
    ON public.property_images FOR SELECT
    USING (true);

CREATE POLICY "Proprietários podem adicionar imagens aos seus imóveis"
    ON public.property_images FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.properties
            WHERE id = property_id AND owner_id = auth.uid()
        )
    );

CREATE POLICY "Proprietários podem atualizar imagens dos seus imóveis"
    ON public.property_images FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.properties
            WHERE id = property_id AND owner_id = auth.uid()
        )
    );

CREATE POLICY "Proprietários podem deletar imagens dos seus imóveis"
    ON public.property_images FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.properties
            WHERE id = property_id AND owner_id = auth.uid()
        )
    );

-- Policies para property_visits
CREATE POLICY "Visitas são visíveis para proprietário e visitante"
    ON public.property_visits FOR SELECT
    USING (
        auth.uid() = visitor_id OR
        EXISTS (
            SELECT 1 FROM public.properties
            WHERE id = property_id AND owner_id = auth.uid()
        )
    );

CREATE POLICY "Clientes podem agendar visitas"
    ON public.property_visits FOR INSERT
    WITH CHECK (auth.uid() = visitor_id);

CREATE POLICY "Proprietários e visitantes podem atualizar visitas"
    ON public.property_visits FOR UPDATE
    USING (
        auth.uid() = visitor_id OR
        EXISTS (
            SELECT 1 FROM public.properties
            WHERE id = property_id AND owner_id = auth.uid()
        )
    );

-- Policies para reviews
CREATE POLICY "Avaliações são visíveis para todos"
    ON public.reviews FOR SELECT
    USING (true);

CREATE POLICY "Usuários autenticados podem criar avaliações"
    ON public.reviews FOR INSERT
    WITH CHECK (auth.uid() = reviewer_id);

CREATE POLICY "Usuários podem atualizar suas próprias avaliações"
    ON public.reviews FOR UPDATE
    USING (auth.uid() = reviewer_id);

CREATE POLICY "Usuários podem deletar suas próprias avaliações"
    ON public.reviews FOR DELETE
    USING (auth.uid() = reviewer_id);